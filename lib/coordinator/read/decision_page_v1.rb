# frozen_string_literal: true

module Coordinator::Read
  class DecisionPageV1 < Value
    attribute :repository_id, Types::RepositoryId
    attribute :topic_id, Types::Identifier.optional
    attribute :policy_status, Types::DecisionPolicyStatus.optional
    attribute :items,
              Types::Array.of(DecisionViewV1)
                .constrained(max_size: Types::DECISION_DISCOVERY_MAXIMUM_ITEMS)
    attribute :next_decision_id, Types::Identifier.optional
    attribute :has_more, Types::Strict::Bool
  end
end
