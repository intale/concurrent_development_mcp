# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class MigrationMetadataV1 < Value
      attribute :command_id, Types::UuidV7
      attribute :actor_kind, Types::String.enum("system")
      attribute :actor_id, Types::Identifier
      attribute :actor_authenticated, Types::Bool
      attribute :recorded_by, Types::String.enum("coordinator")
      attribute :policy_version, Types::String.constrained(min_size: 1, max_size: 200)
      attribute :migration_id, Types::UuidV7
      attribute :migration_source, MigrationSourceV1
      attribute? :canonical_input_digest, Types::Sha256Digest.optional.default(nil)
    end
  end
end
