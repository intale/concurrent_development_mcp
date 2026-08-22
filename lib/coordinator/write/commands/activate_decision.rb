# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class ActivateDecision < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :decision_id, Types::Identifier
      attribute :interpretation_id, Types::Identifier
      attribute :rationale, Decisions::DecisionActivationRationaleV1
    end
  end
end
