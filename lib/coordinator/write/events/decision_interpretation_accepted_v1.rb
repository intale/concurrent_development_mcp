# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DecisionInterpretationAcceptedV1 < Base
      contract type: "DecisionInterpretationAccepted", version: 1

      attribute :interpretation_id, Types::Identifier
      attribute :source_message_id, Types::Identifier
      attribute :proposal_event, EventReference
      attribute :slot, Interpretations::InterpretationSlotV1
      attribute :rationale, Interpretations::AdjudicationRationaleV1
      attribute :accepted_at, Types::Timestamp
    end
  end
end
