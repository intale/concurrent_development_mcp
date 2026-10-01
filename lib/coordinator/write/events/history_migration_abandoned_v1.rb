# frozen_string_literal: true

module Coordinator::Write
  module Events
    class HistoryMigrationAbandonedV1 < Base
      contract type: "HistoryMigrationAbandoned", version: 1

      attribute :migration_id, Types::UuidV7
      attribute :reason, Types::String.constrained(min_size: 1, max_size: 2_000)
    end
  end
end
