# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class InterpretationProposalV2 < EventMetadata
      attribute :classifier, Interpretations::ClassifierAttributionV1
      attribute :scope_provenance, Interpretations::DecisionScopeProvenanceV1
    end
  end
end
