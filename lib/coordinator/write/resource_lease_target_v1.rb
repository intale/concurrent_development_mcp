# frozen_string_literal: true

module Coordinator::Write
  class ResourceLeaseTargetV1 < Value
    attribute :resource_id, Types::ResourceId
    attribute :base_blob_oid, Types::GitOid.optional
  end
end
