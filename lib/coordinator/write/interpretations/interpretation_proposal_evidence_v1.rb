# frozen_string_literal: true

module Coordinator::Write
  module Interpretations
    class InterpretationProposalEvidenceV1 < Value
      attribute :proposal,
                Types.Instance(Events::DecisionInterpretationProposedV1) |
                  Types.Instance(Events::DecisionInterpretationProposedV2)
      attribute :event, EventReference
    end
  end
end
