# frozen_string_literal: true

module Coordinator::Write
  module Events
    class HistoryMigrationCompletedV1 < Base
      contract type: "HistoryMigrationCompleted", version: 1

      attribute :migration_id, Types::UuidV7
    end
  end
end
