# frozen_string_literal: true

module Coordinator::Processes
  module Subscriptions
    class HistoryMigrationPageLifecycle < Coordinator::Shared::Subscriptions::Registration
      DEFINITION = ProcessDefinition.new(
        set_name: ProcessManagerSet::SET_NAME,
        subscription_name: "history-migration-page-lifecycle-v1",
        streams: [
          Coordinator::Shared::Subscriptions::StreamFilter.new(
            context: "CoordinatorMaintenance",
            stream_name: "HistoryMigrationPage"
          )
        ],
        event_types: %w[
          HistoryMigrationPageSourceEventCountRecorded
          HistoryMigrationPagePlanned
          HistoryMigrationPageDependencyWaveApplied
        ]
      )

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end
