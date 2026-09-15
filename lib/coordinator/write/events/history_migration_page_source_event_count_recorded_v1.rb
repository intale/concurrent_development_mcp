# frozen_string_literal: true

module Coordinator::Write
  module Events
    class HistoryMigrationPageSourceEventCountRecordedV1 < Base
      contract type: "HistoryMigrationPageSourceEventCountRecorded", version: 1

      attribute :page_id, Types::UuidV7
      attribute :source_event_count, Types::HistoryMigrationSourceEventCount
    end
  end
end
