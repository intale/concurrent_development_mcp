# frozen_string_literal: true

module Coordinator::Write
  class LeaseReferenceV1 < Value
    attribute :lease_id, Types::UuidV7
    attribute :resource_key, Types::String
    attribute :resource_key_hash, Types::Sha256Digest
    attribute :resource_kind, Types::ResourceKind
    attribute :resource_path, Types::ResourcePath
    attribute :base_blob_oid, Types::GitOid.optional
    attribute :fencing_token, Types::FencingToken
  end
end
