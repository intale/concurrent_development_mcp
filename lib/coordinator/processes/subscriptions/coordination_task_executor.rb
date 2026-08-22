# frozen_string_literal: true

module Coordinator::Processes
  module Subscriptions
    class CoordinationTaskExecutor < Coordinator::Shared::Subscriptions::Registration
      DEFINITION = Coordinator::Shared::Subscriptions::Definition.new(
        set_name: ProcessManagerSet::SET_NAME,
        subscription_name: "coordination-task-executor-v1",
        stream_context: "CoordinatorControl",
        stream_name: "CoordinationTask",
        event_type: "CoordinationTaskSubmitted"
      )

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end
