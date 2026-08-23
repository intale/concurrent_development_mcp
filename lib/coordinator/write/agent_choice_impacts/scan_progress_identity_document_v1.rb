# frozen_string_literal: true

module Coordinator::Write
  module AgentChoiceImpacts
    class ScanProgressIdentityDocumentV1 < Value
      attribute :schema, Types::String.enum("agent-choice-impact-scan-progress-identity/v1")
      attribute :policy_version, Types::AgentChoiceImpactPolicyVersion
      attribute :checkpoint_event, EventReference
    end
  end
end
