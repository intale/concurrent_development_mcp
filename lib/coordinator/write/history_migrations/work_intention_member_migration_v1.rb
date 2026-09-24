# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class WorkIntentionMemberMigrationV1 < Value
      attribute :target_stream, StreamReference
      attribute :source_lease_id, Types::UuidV7
      attribute :intention_id, Types::UuidV7
      attribute :resource_id, Types::ResourceId
      attribute :resource_kind, Types::ResourceKind
      attribute :resource_path, Types::ResourcePath
      attribute :base_blob_oid, Types::GitOid.optional
      attribute :fencing_token, Types::FencingToken
    end
  end
end
