# frozen_string_literal: true

module Coordinator::Write
  class LeaseReferenceV2 < Value
    attribute :lease_id, Types::UuidV7
    attribute :resource_id, Types::ResourceId
    attribute :resource_kind, Types::ResourceKind
    attribute :resource_path, Types::ResourcePath
    attribute :base_blob_oid, Types::GitOid.optional
    attribute :fencing_token, Types::FencingToken
  end
end
