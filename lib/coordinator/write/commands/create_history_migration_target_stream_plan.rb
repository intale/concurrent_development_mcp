# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class CreateHistoryMigrationTargetStreamPlan < Value
      attribute :command_id, Types::UuidV7
      attribute :actor, Actor
      attribute :event_id, Types::UuidV7
      attribute :migration_id, Types::UuidV7
      attribute :plan_id, Types::UuidV7
      attribute :target_stream_context, Types::String.constrained(min_size: 1, max_size: 200)
      attribute :target_stream_name, Types::String.constrained(min_size: 1, max_size: 200)
      attribute :target_stream_id, Types::Identifier
    end
  end
end
