# frozen_string_literal: true

class AcceptanceContentionBarrier
  EVENT_NAME = "coordinator.command_boundary"

  def initialize(operation:, command_ids:)
    @operation = operation
    @command_ids = command_ids.to_set.freeze
    @mutex = Thread::Mutex.new
    @condition = Thread::ConditionVariable.new
    @arrivals = {}
    @released_command_ids = Set.new
    @completed_command_ids = Set.new
    @thread_commands = {}
    @task_ids = {}
    @subscriber = ActiveSupport::Notifications.subscribe(EVENT_NAME) do |_name, _start, _finish, _id, payload|
      observe(payload)
    end
    @completion_trace = TracePoint.new(:return) { command_completed(_1) }
    @completion_trace.enable
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

  def release(command_id: nil)
    @mutex.synchronize do
      if command_id
        @released_command_ids.add(command_id.to_s)
      else
        @released_command_ids.merge(@command_ids)
      end
      @condition.broadcast
    end
  end

  def wait_for_completion(command_id, timeout_seconds: LiveSubscriptions::DEFAULT_TIMEOUT_SECONDS)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds

    @mutex.synchronize do
      until @completed_command_ids.include?(command_id.to_s)
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raise completion_timeout_error(command_id) if remaining <= 0

        @condition.wait(@mutex, remaining)
      end
    end
  end

  def close
    release
    @completion_trace.disable
    ActiveSupport::Notifications.unsubscribe(@subscriber)
  end

  private

  def observe(payload)
    command_id = payload.fetch(:command_id).to_s
    if payload.fetch(:operation).to_s == "coordination_task_execute" && @command_ids.include?(command_id)
      @mutex.synchronize { @task_ids[command_id] = payload.fetch(:task_id).to_s }
    end

    arrive(payload) if matches?(payload)
  end

  def matches?(payload)
    payload.fetch(:operation).to_s == @operation && @command_ids.include?(payload.fetch(:command_id).to_s)
  end

  def arrive(payload)
    command_id = payload.fetch(:command_id).to_s
    @mutex.synchronize do
      lane_identity = payload[:task_id] || @task_ids[command_id] || payload[:process_command_id]
      @thread_commands[Thread.current.object_id] = command_id
      @arrivals[command_id] ||= {
        operation: @operation,
        command_id:,
        task_id: payload[:task_id],
        process_command_id: payload[:process_command_id],
        source_event_id: payload[:source_event_id],
        thread_id: Thread.current.object_id,
        worker_lane: lane_identity && Coordinator::Write::Tasks::ExecutionLane.new.index(lane_identity),
        arrived_at: Process.clock_gettime(Process::CLOCK_MONOTONIC)
      }.freeze
      @condition.broadcast
      @condition.wait(@mutex) until @released_command_ids.include?(command_id)
    end
  end

  def timeout_error
    missing = @command_ids - @arrivals.keys
    "Timed out waiting for #{@operation} contention boundary; missing commands: #{missing.to_a.sort.inspect}"
  end

  def command_completed(trace)
    return unless trace.method_id == :call_command
    return unless trace.defined_class.name&.end_with?("::ExecuteReserveWriteSet")

    @mutex.synchronize do
      command_id = @thread_commands.delete(Thread.current.object_id)
      return unless command_id

      @completed_command_ids.add(command_id)
      @condition.broadcast
    end
  end

  def completion_timeout_error(command_id)
    "Timed out waiting for #{@operation} command #{command_id} to leave its transaction"
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

  def release_contention_command(command_id)
    @contention_barrier.release(command_id:)
  end

  def await_contention_command_completion(command_id)
    @contention_barrier.wait_for_completion(command_id)
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
