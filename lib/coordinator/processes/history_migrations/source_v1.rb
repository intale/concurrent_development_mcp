# frozen_string_literal: true

module Coordinator::Processes
  module HistoryMigrations
    class SourceV1 < Value
      Payload = Types.Instance(Coordinator::Write::Events::HistoryMigrationStartedV1) |
                Types.Instance(Coordinator::Write::Events::HistoryMigrationCursorAdvancedV1) |
                Types.Instance(Coordinator::Write::Events::HistoryMigrationPlanCompletedV1) |
                Types.Instance(Coordinator::Write::Events::HistoryMigrationApplicationCursorAdvancedV1) |
                Types.Instance(Coordinator::Write::Events::HistoryMigrationPageSourceEventCountRecordedV1) |
                Types.Instance(Coordinator::Write::Events::HistoryMigrationPagePlannedV1) |
                Types.Instance(Coordinator::Write::Events::HistoryMigrationPageDependencyWaveAppliedV1)

      attribute :event, Types.Instance(PgEventstore::Event)
      attribute :payload, Payload
    end
  end
end
