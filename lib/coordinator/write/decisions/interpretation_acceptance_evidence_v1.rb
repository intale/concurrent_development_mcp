# frozen_string_literal: true

module Coordinator::Write
  module Decisions
    class InterpretationAcceptanceEvidenceV1 < Value
      attribute :acceptance, Events::DecisionInterpretationAcceptedV1
      attribute :event, EventReference
    end
  end
end
