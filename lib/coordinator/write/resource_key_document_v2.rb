# frozen_string_literal: true

module Coordinator::Write
  class ResourceKeyDocumentV2 < Value
    POLICY_VERSION = "coordinator-resource-key/v2"

    attribute :schema, Types::String.enum(POLICY_VERSION)
    attribute :policy_version, Types::String.enum(POLICY_VERSION)
    attribute :scope, Types::String.constrained(min_size: 1, max_size: 500)
    attribute :repository_id, Types::UuidV7
    attribute :kind, Types::ResourceKind
    attribute :path, Types::ResourcePath
  end
end
