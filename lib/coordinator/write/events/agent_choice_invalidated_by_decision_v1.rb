# frozen_string_literal: true

module Coordinator::Write
  module Events
    class AgentChoiceInvalidatedByDecisionV1 < Base
      contract type: "AgentChoiceInvalidatedByDecision", version: 1

      attribute :choice_id, Types::Identifier
      attribute :accepted_choice, EventReference
      attribute :assessment_event, EventReference
      attribute :decision_change_event, EventReference
      attribute :previous_context_digest, Types::Sha256Digest
      attribute :resulting_context_digest, Types::Sha256Digest
      attribute :reason, Types::AgentChoiceInvalidationReason
      attribute :invalidated_at, Types::Timestamp
    end
  end
end
