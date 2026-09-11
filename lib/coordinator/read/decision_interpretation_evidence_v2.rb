# frozen_string_literal: true

module Coordinator::Read
  class DecisionInterpretationEvidenceV2 < Value
    attribute :source_event, Coordinator::Write::EventReference
    attribute :proposal_event, Coordinator::Write::EventReference
    attribute :acceptance_event, Coordinator::Write::EventReference
    attribute :classifier, Coordinator::Write::Interpretations::ClassifierAttributionV1
    attribute :scope_provenance, Coordinator::Write::Interpretations::DecisionScopeProvenanceV1
  end
end
