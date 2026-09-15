# frozen_string_literal: true

module Coordinator::Write
  module Events
    class HistoryMigrationPagePlannedV1 < Base
      contract type: "HistoryMigrationPagePlanned", version: 1

      attribute :page_id, Types::UuidV7
    end
  end
end
