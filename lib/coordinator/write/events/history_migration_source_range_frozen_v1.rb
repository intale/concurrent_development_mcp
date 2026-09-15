# frozen_string_literal: true

module Coordinator::Write
  module Events
    class HistoryMigrationSourceRangeFrozenV1 < Base
      contract type: "HistoryMigrationSourceRangeFrozen", version: 1

      attribute :migration_id, Types::UuidV7
      attribute :source_upper_position, Types::GlobalPosition.optional
    end
  end
end
