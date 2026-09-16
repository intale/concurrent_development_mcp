# frozen_string_literal: true

module Coordinator::Write
  module Events
    class HistoryMigrationTargetStreamPlanCreatedV1 < Base
      contract type: "HistoryMigrationTargetStreamPlanCreated", version: 1

      attribute :migration_id, Types::UuidV7
      attribute :plan_id, Types::UuidV7
      attribute :target_stream_context, Types::String.constrained(min_size: 1, max_size: 200)
      attribute :target_stream_name, Types::String.constrained(min_size: 1, max_size: 200)
      attribute :target_stream_id, Types::Identifier
    end
  end
end
