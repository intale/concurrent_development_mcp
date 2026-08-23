# frozen_string_literal: true

module Coordinator::Read
  class AgentChoiceInvalidationViewV1 < Value
    attribute :assessment_event, Coordinator::Write::EventReference
    attribute :decision_change_event, Coordinator::Write::EventReference
    attribute :previous_context_digest, Types::Sha256Digest
    attribute :resulting_context_digest, Types::Sha256Digest
    attribute :reason, Types::AgentChoiceInvalidationReason
    attribute :evidence, AgentChoiceLifecycleEvidenceV1
  end
end
