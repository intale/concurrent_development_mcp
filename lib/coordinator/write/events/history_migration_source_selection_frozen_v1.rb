# frozen_string_literal: true

module Coordinator::Write
  module Events
    class HistoryMigrationSourceSelectionFrozenV1 < Base
      contract type: "HistoryMigrationSourceSelectionFrozen", version: 1

      attribute :migration_id, Types::UuidV7
      attribute :source_after_position, Types::GlobalPosition
      attribute :source_command_ids, Types::Array.of(Types::UuidV7).constrained(min_size: 1, max_size: 100)
    end
  end
end
