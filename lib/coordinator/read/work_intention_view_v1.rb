# frozen_string_literal: true

module Coordinator::Read
  class WorkIntentionViewV1 < Value
    attribute :intention_id, Types::UuidV7
    attribute :resource_id, Types::ResourceId
    attribute :resource_kind, Types::ResourceKind
    attribute :resource_path, Types::ResourcePath
    attribute :base_blob_oid, Types::GitOid.optional
    attribute :mode, Types::WorkIntentionMode
    attribute :purpose, Types::WorkIntentionPurpose
    attribute :context, Types::WorkIntentionContext.optional
    attribute :fencing_token, Types::FencingToken
  end
end
