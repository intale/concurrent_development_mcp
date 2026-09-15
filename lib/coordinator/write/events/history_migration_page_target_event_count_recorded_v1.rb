# frozen_string_literal: true

module Coordinator::Write
  module Events
    class HistoryMigrationPageTargetEventCountRecordedV1 < Base
      contract type: "HistoryMigrationPageTargetEventCountRecorded", version: 1

      attribute :page_id, Types::UuidV7
      attribute :target_event_count, Types::HistoryMigrationTargetEventCount
    end
  end
end
