# frozen_string_literal: true

module Coordinator::Write
  class LeaseResourceV2 < Value
    POLICY_VERSION = "coordinator-resource-lease/v2"

    attribute :resource_id, Types::ResourceId
    attribute :kind, Types::ResourceKind
    attribute :path, Types::ResourcePath
    attribute :base_blob_oid, Types::GitOid.optional
    attribute :policy_version, Types::String.enum(POLICY_VERSION)
  end
end
