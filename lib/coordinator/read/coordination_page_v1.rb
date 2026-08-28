# frozen_string_literal: true

module Coordinator::Read
  class CoordinationPageV1 < Value
    class Cursor < Value
      attribute :through_last_processed_at, Types::Timestamp
      attribute :after_last_processed_at, Types::Timestamp
      attribute :after_change_set_id, Types::Identifier
    end

    attribute :scope, Types::String.constrained(min_size: 1, max_size: 500)
    attribute :repository_id, Types::RepositoryId.optional
    attribute :statuses,
              Types::Array.of(Types::String.enum("planning", "active", "completed"))
                .constrained(min_size: 1, max_size: 3)
    attribute :items,
              Types::Array.of(CoordinationSummaryV1)
                .constrained(max_size: Types::COORDINATION_DISCOVERY_MAXIMUM_ITEMS)
    attribute :continuation_cursor, Cursor.optional
    attribute :has_more, Types::Strict::Bool
  end
end
