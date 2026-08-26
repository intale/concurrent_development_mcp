# frozen_string_literal: true

module LiveSubscriptions
  DEFAULT_TIMEOUT_SECONDS = 15
  POLL_INTERVAL_SECONDS = 0.05
  TERMINAL_TASK_STATUSES = %w[cancelled completed failed].freeze

  def live_subscriptions!
    @live_subscriptions_enabled = true
  end

  def start_live_subscriptions
    assert_acceptance(@live_subscriptions_enabled, "Scenario is not tagged for live subscriptions")
    return if @live_subscription_sets

    @live_subscription_sets = [
      Coordinator::Container["subscription_sets.process_managers"],
      Coordinator::Container["subscription_sets.read_models"]
    ]
    started = []
    @live_subscription_sets.each do |subscription_set|
      subscription_set.start
      started << subscription_set
    end
  rescue StandardError
    started.reverse_each(&:stop)
    @live_subscription_sets = nil
    raise
  end

  def stop_live_subscriptions
    @live_subscription_sets&.reverse_each(&:stop)
    @live_subscription_sets = nil
  end

  def eventually(label, timeout_seconds: DEFAULT_TIMEOUT_SECONDS)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds
    last_observation = nil

    loop do
      matched, last_observation = yield
      return last_observation if matched

      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        raise "Timed out waiting for #{label}; last observation: #{last_observation.inspect}"
      end

      sleep POLL_INTERVAL_SECONDS
    end
  end

  def await_task_terminal(task_id)
    eventually("Task #{task_id} to reach a terminal state") do
      state = task_request("tasks/get", task_id)
      [ TERMINAL_TASK_STATUSES.include?(state.dig("result", "status")), state ]
    end
  end
end

World(LiveSubscriptions)

Before("@live-subscriptions") do
  live_subscriptions!
end

After("@live-subscriptions") do
  stop_live_subscriptions
end
