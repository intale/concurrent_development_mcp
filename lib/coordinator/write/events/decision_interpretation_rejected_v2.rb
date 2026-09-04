# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DecisionInterpretationRejectedV2 < Base
      contract type: "DecisionInterpretationRejected", version: 2

      attribute :interpretation_id, Types::Identifier
      attribute :source_message_id, Types::Identifier
      attribute :rationale, Types::InterpretationDescription
    end
  end
end
