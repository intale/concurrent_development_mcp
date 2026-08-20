# frozen_string_literal: true

module Coordinator
  module Subscriptions
    class ChangeSetReadiness
      DEFINITION = Definition.new(
        set_name: "coordinator-process-managers-v1",
        subscription_name: "change-set-readiness-v1",
        stream_context: "DevelopmentPlanning",
        stream_name: "ChangeSet",
        event_type: "ChangeSetActivated"
      )

      def initialize(handler:, pull_interval: 1.0)
        @manager = PgEventstore.subscriptions_manager(subscription_set: DEFINITION.set_name)
        @manager.subscribe(
          DEFINITION.subscription_name,
          handler:,
          options: DEFINITION.options,
          pull_interval:
        )
        @runner = nil
      end

      def start
        @runner = @manager.start!
      end

      def stop
        @runner&.stop
        @runner = nil
        nil
      end

      def processed_event_count
        subscription = @manager.subscriptions.find { _1.name == DEFINITION.subscription_name }
        subscription&.total_processed_events || 0
      end
    end
  end
end
