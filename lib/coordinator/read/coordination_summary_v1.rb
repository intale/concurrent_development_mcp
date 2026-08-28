# frozen_string_literal: true

module Coordinator::Read
  class CoordinationSummaryV1 < Value
    attribute :scope, Types::String.constrained(min_size: 1, max_size: 500)
    attribute :change_set_id, Types::Identifier
    attribute :status, Types::String.enum("planning", "active", "completed")
    attribute :goal, Types::Goal
    attribute :repository_ids, Types::ScopeRepositoryIds
    attribute :work_item_ids, Types::WorkItemIds
    attribute :active_attempt_ids, Types::Array.of(Types::Identifier).constrained(max_size: 100)
    attribute :candidate_checkpoint_count, Types::Integer.constrained(gteq: 0, lteq: 100)
    attribute :created_at, Types::Timestamp
    attribute :activated_at, Types::Timestamp.optional
    attribute :completed_at, Types::Timestamp.optional
    attribute :last_processed_at, Types::Timestamp
  end
end
