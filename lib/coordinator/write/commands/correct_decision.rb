# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class CorrectDecision < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :decision_id, Types::Identifier
      attribute :interpretation_id, Types::Identifier
      attribute :expected_head, EventReference
      attribute :rationale, Decisions::DecisionCorrectionRationaleV1
    end
  end
end
