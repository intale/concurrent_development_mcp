# frozen_string_literal: true

module Coordinator::Read
  class InterpretationProjectionSourceV2 < Value
    Ambiguity = Coordinator::Write::Interpretations::InterpretationAmbiguityV1

    attribute :proposal, Coordinator::Write::Events::DecisionInterpretationProposedV2
    attribute :source_event, Coordinator::Write::EventReference
    attribute :source_span, Coordinator::Write::Interpretations::SourceSpanV1
    attribute :classifier, Coordinator::Write::Interpretations::ClassifierAttributionV1
    attribute :scope_provenance, Coordinator::Write::Interpretations::DecisionScopeProvenanceV1
    attribute :ambiguities, Types::Array.of(Ambiguity).constrained(max_size: 20)
    attribute :assessment, Coordinator::Write::Interpretations::InterpretationAssessmentV1
    attribute :proposed_at, Types::Timestamp
  end
end
