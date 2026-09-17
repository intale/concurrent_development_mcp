# frozen_string_literal: true

module Coordinator::Write
  module Events
    class HistoryMigrationPageDependencyWaveAppliedV1 < Base
      contract type: "HistoryMigrationPageDependencyWaveApplied", version: 1

      attribute :page_id, Types::UuidV7
      attribute :dependency_wave, Types::HistoryMigrationDependencyWave
      attribute :target_event_count, Types::HistoryMigrationWaveTargetEventCount
    end
  end
end
