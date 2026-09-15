# frozen_string_literal: true

module Coordinator::Write
  module Events
    class HistoryMigrationPlanCompletedV1 < Base
      contract type: "HistoryMigrationPlanCompleted", version: 1

      attribute :migration_id, Types::UuidV7
    end
  end
end
