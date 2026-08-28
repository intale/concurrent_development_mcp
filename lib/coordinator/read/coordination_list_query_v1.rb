# frozen_string_literal: true

module Coordinator::Read
  class CoordinationListQueryV1 < Value
    attribute :scope, Types::String.constrained(min_size: 1, max_size: 500)
    attribute :repository_id, Types::RepositoryId.optional
    attribute :statuses,
              Types::Array.of(Types::String.enum("planning", "active", "completed"))
                .constrained(min_size: 1, max_size: 3)
    attribute :cursor, CoordinationPageV1::Cursor.optional
    attribute :limit,
              Types::Integer.constrained(
                gteq: 1,
                lteq: Types::COORDINATION_DISCOVERY_MAXIMUM_ITEMS
              )
  end
end
