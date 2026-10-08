# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class StartHistoryMigration < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :migration_id, Types::UuidV7
      attribute :source_config_name, Types::Identifier
      attribute :target_config_name, Types::Identifier
      attribute :source_upper_position, Types::GlobalPosition.optional
      attribute :page_size, Types::HistoryMigrationPageSize
      attribute :source_after_position, Types::GlobalPosition.optional.default(nil)
      attribute :source_command_ids, Types::Array.of(Types::UuidV7).constrained(max_size: 100).default([].freeze)
    end
  end
end
