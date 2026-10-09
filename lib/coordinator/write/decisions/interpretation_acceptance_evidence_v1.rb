# frozen_string_literal: true

module Coordinator::Write
  module Decisions
    class InterpretationAcceptanceEvidenceV1 < Value
      attribute :acceptance, Types.Instance(Events::DecisionInterpretationAcceptedV2)
      attribute :event, EventReference
    end
  end
end
