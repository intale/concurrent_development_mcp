# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DecisionInterpretationRejectedV1 < Base
      contract type: "DecisionInterpretationRejected", version: 1

      attribute :interpretation_id, Types::Identifier
      attribute :source_message_id, Types::Identifier
      attribute :proposal_event, EventReference
      attribute :rationale, Interpretations::AdjudicationRationaleV1
      attribute :rejected_at, Types::Timestamp
    end
  end
end
