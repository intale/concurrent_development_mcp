# frozen_string_literal: true

module Coordinator::Write
  module Events
    class HistoryMigrationPageSizeSelectedV1 < Base
      contract type: "HistoryMigrationPageSizeSelected", version: 1

      attribute :migration_id, Types::UuidV7
      attribute :page_size, Types::HistoryMigrationPageSize
    end
  end
end
