# frozen_string_literal: true

module Coordinator::Write
  module Events
    class HistoryMigrationCursorAdvancedV1 < Base
      contract type: "HistoryMigrationCursorAdvanced", version: 1

      attribute :migration_id, Types::UuidV7
      attribute :next_from_position, Types::GlobalPosition
    end
  end
end
