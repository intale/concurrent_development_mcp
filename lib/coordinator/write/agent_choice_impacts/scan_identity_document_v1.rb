# frozen_string_literal: true

module Coordinator::Write
  module AgentChoiceImpacts
    class ScanIdentityDocumentV1 < Value
      attribute :schema, Types::String.enum("agent-choice-impact-scan-identity/v1")
      attribute :policy_version, Types::AgentChoiceImpactPolicyVersion
      attribute :source_event, EventReference
    end
  end
end
