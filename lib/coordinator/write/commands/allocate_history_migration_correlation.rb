# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class AllocateHistoryMigrationCorrelation < Value
      attribute :command_id, Types::UuidV7
      attribute :actor, Actor
      attribute :event_id, Types::UuidV7
      attribute :migration_id, Types::UuidV7
      attribute :source_config_name, Types::Identifier
      attribute :source_correlation_id, Types::String.constrained(min_size: 1, max_size: 255)
      attribute :target_correlation_id, Types::UuidV7
    end
  end
end
