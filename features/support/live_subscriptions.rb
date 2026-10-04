# frozen_string_literal: true

module LiveSubscriptions
  DEFAULT_TIMEOUT_SECONDS = 15
  HIGH_VOLUME_TIMEOUT_SECONDS = 180
  POLL_INTERVAL_SECONDS = 0.05
  TERMINAL_TASK_STATUSES = %w[cancelled completed failed].freeze

  def live_subscriptions!
    @live_subscriptions_enabled = true
  end

  def start_live_subscriptions
    start_process_subscriptions
    start_task_result_subscriptions
    start_read_model_subscriptions
  end

  def start_process_subscriptions
    start_subscription_set(:process_managers, "subscription_set_factories.process_managers")
  end

  def start_read_model_subscriptions
    start_subscription_set(:read_models, "subscription_set_factories.read_models")
  end

  def start_task_result_subscriptions
    start_subscription_set(:task_results, "subscription_set_factories.task_results")
  end

  def start_history_replay_subscriptions
    start_subscription_set(
      :history_replay_repositories, "subscription_set_factories.migration_repositories",
      manager: PgEventstore.subscriptions_manager(:migration_target, subscription_set: Coordinator::Read::Subscriptions::ReadModelSet::SET_NAME)
    )
    start_subscription_set(
      :history_replay_receipts, "subscription_set_factories.migration_task_results",
      manager: PgEventstore.subscriptions_manager(:migration_target, subscription_set: Coordinator::Read::Subscriptions::TaskResultSet::SET_NAME)
    )
  end

  def stop_live_subscriptions
    stop_subscription_set(:history_replay_repositories)
    stop_subscription_set(:history_replay_receipts)
    stop_read_model_subscriptions
    stop_task_result_subscriptions
    stop_process_subscriptions
  end

  def stop_process_subscriptions
    stop_subscription_set(:process_managers)
  end

  def stop_read_model_subscriptions
    stop_subscription_set(:read_models)
  end

  def stop_task_result_subscriptions
    stop_subscription_set(:task_results)
  end

  def restart_process_subscriptions
    stop_process_subscriptions
    start_process_subscriptions
  end

  def restart_read_model_subscriptions
    stop_read_model_subscriptions
    start_read_model_subscriptions
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

  def await_task_terminal(task_id, client_id: "default")
    start_task_result_subscriptions
    eventually("Task #{task_id} to reach a terminal state") do
      state = task_request("tasks/get", task_id, client_id:)
      [ TERMINAL_TASK_STATUSES.include?(state.dig("result", "status")), state ]
    end
  rescue RuntimeError => error
    diagnostics = %i[process_managers task_results].to_h do |set_name|
      subscription_set = @live_subscription_sets&.fetch(set_name, nil)
      counts = subscription_set&.subscription_names&.to_h do |name|
        [ name, subscription_set.processed_event_count(name) ]
      end
      [ set_name, counts ]
    end
    raise "#{error.message}; Task subscriptions: #{diagnostics.inspect}"
  end

  def await_read_model(label, timeout_seconds: DEFAULT_TIMEOUT_SECONDS, &predicate)
    owns_subscription_set = !subscription_set_started?(:read_models)
    start_read_model_subscriptions
    eventually(label, timeout_seconds:, &predicate)
  ensure
    stop_read_model_subscriptions if owns_subscription_set
  end

  private

  def subscription_set_started?(key)
    @live_subscription_sets&.key?(key) || false
  end

  def start_subscription_set(key, factory_key, manager: nil)
    @live_subscription_sets ||= {}
    return @live_subscription_sets.fetch(key) if @live_subscription_sets.key?(key)

    subscription_set = Coordinator::Container[factory_key].call(manager:)
    subscription_set.start
    @live_subscription_sets[key] = subscription_set
  rescue StandardError
    subscription_set&.stop
    raise
  end

  def stop_subscription_set(key)
    subscription_set = @live_subscription_sets&.delete(key)
    subscription_set&.stop
    @live_subscription_sets = nil if @live_subscription_sets&.empty?
  end
end

World(LiveSubscriptions)

Before("@live-subscriptions") do
  live_subscriptions!
end

After do
  stop_live_subscriptions
end
