# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ResourceLeaseExpiredV2 < Base
      contract type: "ResourceLeaseExpired", version: 2

      attribute :lease_id, Types::UuidV7
      attribute :lease_set_id, Types::UuidV7
      attribute :resource_id, Types::ResourceId
      attribute :resource_kind, Types::ResourceKind
      attribute :resource_path, Types::ResourcePath
      attribute :policy_version, Types::String.enum(LeaseResourceV2::POLICY_VERSION)
      attribute :mode, Types::LeaseMode
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :agent_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :object_format, Types::GitObjectFormat
      attribute :base_commit_oid, Types::GitOid
      attribute :base_blob_oid, Types::GitOid.optional
      attribute :fencing_token, Types::FencingToken
      attribute :acquired_at, Types::Timestamp
      attribute :renewed_at, Types::Timestamp.optional
      attribute :expires_at, Types::Timestamp
      attribute :expired_at, Types::Timestamp
    end
  end
end
