# frozen_string_literal: true

module Coordinator::Write
  module AgentChoices
    class PolicyEvaluationV1 < Value
      Head = Decisions::DecisionHeadV1
      Warning = Types::String.constrained(min_size: 1, max_size: 500)

      attribute :status, Types::AgentChoicePolicyEvaluationStatus
      attribute :effective_decision, Head.optional
      attribute :contributing_decisions, Types::Array.of(Head).constrained(max_size: 64)
      attribute :basis, Types::AgentChoicePolicyEvaluationBasis
      attribute :warnings, Types::Array.of(Warning).constrained(max_size: 10)
      attribute :reason_codes,
                Types::Array.of(Types::AgentChoicePolicyReasonCode).constrained(min_size: 1, max_size: 10)
    end
  end
end
