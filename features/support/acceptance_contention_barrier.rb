# frozen_string_literal: true

class AcceptanceContentionBarrier
  EVENT_NAME = "coordinator.command_boundary"

  def initialize(operation:, command_ids:)
    @operation = operation
    @command_ids = command_ids.to_set.freeze
    @mutex = Thread::Mutex.new
    @condition = Thread::ConditionVariable.new
    @arrivals = {}
    @released = false
    @subscriber = ActiveSupport::Notifications.subscribe(EVENT_NAME) do |_name, _start, _finish, _id, payload|
      arrive(payload) if matches?(payload)
    end
  end

  def wait(timeout_seconds: LiveSubscriptions::DEFAULT_TIMEOUT_SECONDS)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds

    @mutex.synchronize do
      until @arrivals.length == @command_ids.length
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raise timeout_error if remaining <= 0

        @condition.wait(@mutex, remaining)
      end

      @arrivals.values.sort_by { _1.fetch(:command_id) }.map(&:dup).freeze
    end
  end

  def release
    @mutex.synchronize do
      @released = true
      @condition.broadcast
    end
  end

  def close
    release
    ActiveSupport::Notifications.unsubscribe(@subscriber)
  end

  private

  def matches?(payload)
    payload.fetch(:operation).to_s == @operation && @command_ids.include?(payload.fetch(:command_id).to_s)
  end

  def arrive(payload)
    command_id = payload.fetch(:command_id).to_s
    @mutex.synchronize do
      @arrivals[command_id] ||= {
        operation: @operation,
        command_id:,
        task_id: payload[:task_id],
        thread_id: Thread.current.object_id,
        worker_lane: Coordinator::Write::Tasks::ExecutionLane.new.index(command_id),
        arrived_at: Process.clock_gettime(Process::CLOCK_MONOTONIC)
      }.freeze
      @condition.broadcast
      @condition.wait(@mutex) until @released
    end
  end

  def timeout_error
    missing = @command_ids - @arrivals.keys
    "Timed out waiting for #{@operation} contention boundary; missing commands: #{missing.to_a.sort.inspect}"
  end
end

module AcceptanceContentionBarrierWorld
  def install_contention_barrier(operation:, command_ids:)
    close_contention_barrier
    @contention_barrier = AcceptanceContentionBarrier.new(operation:, command_ids:)
  end

  def await_contention_evidence
    @contention_evidence = @contention_barrier.wait
  end

  def release_contention_barrier
    @contention_barrier.release
  end

  def close_contention_barrier
    @contention_barrier&.close
    @contention_barrier = nil
  end
end

World(AcceptanceContentionBarrierWorld)

After do
  close_contention_barrier
end
