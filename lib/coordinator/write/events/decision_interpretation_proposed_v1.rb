# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DecisionInterpretationProposedV1 < Base
      contract type: "DecisionInterpretationProposed", version: 1

      Ambiguity = Interpretations::InterpretationAmbiguityV1

      attribute :interpretation_id, Types::Identifier
      attribute :source_message_id, Types::Identifier
      attribute :source_event, EventReference
      attribute :source_span, Interpretations::SourceSpanV1.optional
      attribute :classifier, Interpretations::ClassifierAttributionV1
      attribute :proposed_decision, Interpretations::ProposedDecisionV1
      attribute :scope_provenance, Interpretations::DecisionScopeProvenanceV1
      attribute :ambiguities, Types::Array.of(Ambiguity).constrained(max_size: 20)
      attribute :assessment, Interpretations::InterpretationAssessmentV1
      attribute :proposed_at, Types::Timestamp
    end
  end
end
