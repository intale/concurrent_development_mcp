# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DecisionClarificationRequiredV2 < Base
      contract type: "DecisionClarificationRequired", version: 2

      attribute :interpretation_id, Types::Identifier
      attribute :source_message_id, Types::Identifier
      attribute :origin, Types::InterpretationClarificationOrigin
      attribute :reasons, Types::InterpretationReasons
      attribute :questions,
                Types::Array.of(Types::InterpretationDescription).constrained(min_size: 1, max_size: 20)
      attribute :rationale, Types::InterpretationDescription
    end
  end
end
