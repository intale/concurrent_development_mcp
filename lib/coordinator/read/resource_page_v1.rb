# frozen_string_literal: true

module Coordinator::Read
  class ResourcePageV1 < Value
    attribute :repository_id, Types::RepositoryId
    attribute :items, Types::Array.of(ResourceViewV1).constrained(max_size: 100)
    attribute :next_resource_id, Types::ResourceId.optional
    attribute :has_more, Types::Bool
  end
end
