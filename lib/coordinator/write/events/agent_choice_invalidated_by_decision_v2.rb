# frozen_string_literal: true

module Coordinator::Write
  module Events
    class AgentChoiceInvalidatedByDecisionV2 < Base
      contract type: "AgentChoiceInvalidatedByDecision", version: 2

      attribute :choice_id, Types::Identifier
      attribute :reason, Types::AgentChoiceInvalidationReason
    end
  end
end
