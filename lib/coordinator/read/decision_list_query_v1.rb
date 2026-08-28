# frozen_string_literal: true

module Coordinator::Read
  class DecisionListQueryV1 < Value
    attribute :repository_id, Types::RepositoryId
    attribute :topic_id, Types::Identifier.optional
    attribute :policy_status, Types::DecisionPolicyStatus.optional
    attribute :after_decision_id, Types::Identifier.optional
    attribute :limit,
              Types::Integer.constrained(
                gteq: 1,
                lteq: Types::DECISION_DISCOVERY_MAXIMUM_ITEMS
              )
  end
end
