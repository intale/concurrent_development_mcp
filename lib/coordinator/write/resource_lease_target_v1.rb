# frozen_string_literal: true

module Coordinator::Write
  class ResourceLeaseTargetV1 < Value
    attribute :resource_id, Types::ResourceId
    attribute :base_blob_oid, Types::GitOid.optional
    attribute :mode, Types::String.default("shared".freeze).enum("shared", "exclusive")
    attribute :purpose,
              Types::String.default("Coordinate changes to this resource".freeze)
                .constrained(min_size: 1, max_size: 1_000)
    attribute :context, Types::WorkIntentionContext.optional.default(nil)
  end
end
