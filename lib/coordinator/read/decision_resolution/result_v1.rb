# frozen_string_literal: true

module Coordinator::Read
  module DecisionResolution
    class ResultV1 < Value
      Head = Coordinator::Write::Decisions::DecisionHeadV1

      attribute :effective_decision, ResolvedDecisionV1.optional
      attribute :shadowed_decisions, Types::Array.of(ShadowedDecisionV1).constrained(max_size: 32)
      attribute :conflict, ConflictV1.optional
      attribute :unsupported_dimensions, Types::Array.of(Types::Identifier).constrained(max_size: 32)
      attribute :unsupported_decisions, Types::Array.of(Head).constrained(max_size: 32)
      attribute :unresolved_decisions, Types::Array.of(Head).constrained(max_size: 32)
    end
  end
end
