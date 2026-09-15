# frozen_string_literal: true

module Coordinator::Write
  module Events
    class HistoryMigrationCreatedV1 < Base
      contract type: "HistoryMigrationCreated", version: 1

      attribute :migration_id, Types::UuidV7
    end
  end
end
