# frozen_string_literal: true

module Coordinator::Write
  module Interpretations
    class InterpretationProposalEvidenceV1 < Value
      attribute :proposal, Events::DecisionInterpretationProposedV1
      attribute :event, EventReference
    end
  end
end
