# frozen_string_literal: true

module Coordinator::Read
  class ResourceListQueryV1 < Value
    attribute :repository_id, Types::RepositoryId
    attribute :kind, Types::ResourceKind.optional
    attribute :lifecycle_status, Types::String.enum("registered", "current", "inactive").optional
    attribute :after_resource_id, Types::ResourceId.optional
    attribute :limit, Types::Integer.constrained(gteq: 1, lteq: 100)
  end
end
