# frozen_string_literal: true

module Coordinator::Write
  class ResourceKeyDocumentV1 < Value
    POLICY_VERSION = "coordinator-resource-key/v1"

    attribute :schema, Types::String.enum(POLICY_VERSION)
    attribute :policy_version, Types::String.enum(POLICY_VERSION)
    attribute :repository_id, Types::RepositoryId
    attribute :kind, Types::ResourceKind
    attribute :path, Types::ResourcePath
  end
end
