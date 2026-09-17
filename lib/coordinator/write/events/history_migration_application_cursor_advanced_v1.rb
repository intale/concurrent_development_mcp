# frozen_string_literal: true

module Coordinator::Write
  module Events
    class HistoryMigrationApplicationCursorAdvancedV1 < Base
      contract type: "HistoryMigrationApplicationCursorAdvanced", version: 1

      attribute :migration_id, Types::UuidV7
      attribute :dependency_wave, Types::HistoryMigrationDependencyWave
      attribute :next_from_position, Types::GlobalPosition
    end
  end
end
