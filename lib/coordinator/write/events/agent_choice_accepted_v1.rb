# frozen_string_literal: true

module Coordinator::Write
  module Events
    class AgentChoiceAcceptedV1 < Base
      contract type: "AgentChoiceAccepted", version: 1

      attribute :choice_id, Types::Identifier
      attribute :recorded_event, EventReference
      attribute :context_digest, Types::Sha256Digest
      attribute :assessment, AgentChoices::ChoiceAssessmentV1
      attribute :accepted_at, Types::Timestamp
    end
  end
end
