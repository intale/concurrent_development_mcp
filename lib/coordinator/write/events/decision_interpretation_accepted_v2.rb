# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DecisionInterpretationAcceptedV2 < Base
      contract type: "DecisionInterpretationAccepted", version: 2

      attribute :interpretation_id, Types::Identifier
      attribute :source_message_id, Types::Identifier
      attribute :slot, Interpretations::InterpretationSlotV1
      attribute :rationale, Types::InterpretationDescription
    end
  end
end
