# frozen_string_literal: true

module Coordinator::Write
  class WorkIntentionResourceV1 < Value
    attribute :resource_id, Types::ResourceId
    attribute :kind, Types::ResourceKind
    attribute :path, Types::ResourcePath
    attribute :base_blob_oid, Types::GitOid.optional
  end
end
