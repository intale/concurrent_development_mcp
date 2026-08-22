# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ResourceLeaseRenewedV1 < Base
      contract type: "ResourceLeaseRenewed", version: 1

      attribute :lease_id, Types::UuidV7
      attribute :lease_set_id, Types::UuidV7
      attribute :resource_key, Types::String
      attribute :resource_key_hash, Types::Sha256Digest
      attribute :resource_kind, Types::ResourceKind
      attribute :resource_path, Types::ResourcePath
      attribute :policy_version, Types::String.enum(ResourceKeyDocumentV1::POLICY_VERSION)
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
      attribute :renewed_at, Types::Timestamp
      attribute :previous_expires_at, Types::Timestamp
      attribute :expires_at, Types::Timestamp
    end
  end
end
