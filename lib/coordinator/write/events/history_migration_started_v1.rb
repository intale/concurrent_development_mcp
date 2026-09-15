# frozen_string_literal: true

module Coordinator::Write
  module Events
    class HistoryMigrationStartedV1 < Base
      contract type: "HistoryMigrationStarted", version: 1

      attribute :migration_id, Types::UuidV7
    end
  end
end
