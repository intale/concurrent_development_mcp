# frozen_string_literal: true

module Coordinator::Write
  module Events
    class HistoryMigrationStreamIdentityAllocatedV1 < Base
      contract type: "HistoryMigrationStreamIdentityAllocated", version: 1

      attribute :migration_id, Types::UuidV7
      attribute :source_config_name, Types::Identifier
      attribute :source_stream_context, Types::String.constrained(min_size: 1, max_size: 200)
      attribute :source_stream_name, Types::String.constrained(min_size: 1, max_size: 200)
      attribute :source_stream_id, Types::String.constrained(min_size: 1, max_size: 2_048)
      attribute :source_stream_starting_position, Types::GlobalPosition
      attribute :target_stream_context, Types::String.constrained(min_size: 1, max_size: 200)
      attribute :target_stream_name, Types::String.constrained(min_size: 1, max_size: 200)
      attribute :identity_role, Types::Identifier
      attribute :target_stream_id, Types::UuidV7
    end
  end
end
