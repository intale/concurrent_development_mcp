# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class ResolveHistoryMigrationSourceTrace < Value
      attribute :command_id, Types::UuidV7
      attribute :actor, Actor
      attribute :event_id, Types::UuidV7
      attribute :trace_id, Types::UuidV7
      attribute :migration_id, Types::UuidV7
      attribute :source_event_id, Types::UuidV7
      attribute :source_global_position, Types::GlobalPosition
      attribute :source_causation_id, Types::UuidV7.optional
      attribute :target_endpoint, EventReference.optional
    end
  end
end
