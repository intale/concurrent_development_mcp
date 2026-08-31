# frozen_string_literal: true

module Coordinator::Read::Web
  class ProjectResourcesQueryV1 < Coordinator::Shared::Value
    attribute :repository_id, Coordinator::Shared::Types::UuidV7
    attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 100)
    attribute :resource_after_id, Coordinator::Shared::Types::UuidV7.optional
    attribute :lease_after_id, Coordinator::Shared::Types::UuidV7.optional
    attribute :lease_as_of, Coordinator::Shared::Types::Timestamp
    attribute :resource_kind,
              Coordinator::Shared::Types::String.enum("file", "directory").optional
    attribute :resource_lifecycle_status,
              Coordinator::Shared::Types::String.enum("registered", "current", "inactive").optional
  end
end
