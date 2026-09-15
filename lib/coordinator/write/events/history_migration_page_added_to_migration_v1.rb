# frozen_string_literal: true

module Coordinator::Write
  module Events
    class HistoryMigrationPageAddedToMigrationV1 < Base
      contract type: "HistoryMigrationPageAddedToMigration", version: 1

      attribute :page_id, Types::UuidV7
      attribute :migration_id, Types::UuidV7
    end
  end
end
