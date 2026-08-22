# frozen_string_literal: true

module Coordinator::Write
  module DecisionContexts
    class ResolvedDecisionV1 < Value
      ANCHOR_KINDS = %w[workspace repository change_set work_item attempt].freeze

      attribute :head, Decisions::DecisionHeadV1
      attribute :definition_digest, Types::Sha256Digest
      attribute :topic_id, Types::String.enum("testing.framework")
      attribute :effect, Types::DecisionEffect
      attribute :modality, Types::DecisionModality
      attribute :value, Interpretations::DecisionValueV1
      attribute :enforcement, Interpretations::DecisionEnforcementV1
      attribute :anchor_kind, Types::String.enum(*ANCHOR_KINDS)
      attribute :anchor_rank, Types::Integer.constrained(gteq: 1, lteq: 5)
      attribute :applicability_reasons,
                Types::Array.of(Types::Identifier).constrained(min_size: 1, max_size: 10)
    end
  end
end
