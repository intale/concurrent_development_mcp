# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DecisionInterpretationProposedV2 < Base
      contract type: "DecisionInterpretationProposed", version: 2

      attribute :interpretation_id, Types::Identifier
      attribute :source_message_id, Types::Identifier
      attribute :source_span, Types::GuidanceText
      attribute :proposed_decision, Interpretations::ProposedDecisionV1
      attribute :assessment, Types::InterpretationAssessmentStatus
      attribute :ambiguities,
                Types::Array.of(Types::InterpretationDescription).constrained(max_size: 20)
    end
  end
end
