# frozen_string_literal: true

module Coordinator::Write
  module Events
    class HistoryMigrationCorrelationAllocatedV1 < Base
      contract type: "HistoryMigrationCorrelationAllocated", version: 1

      attribute :migration_id, Types::UuidV7
      attribute :source_config_name, Types::Identifier
      attribute :source_correlation_id, Types::String.constrained(min_size: 1, max_size: 255)
      attribute :target_correlation_id, Types::UuidV7
    end
  end
end
