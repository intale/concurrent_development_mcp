# frozen_string_literal: true

module Coordinator::Write
  module Events
    class AgentChoiceImpactScanSkippedV1 < Base
      contract type: "AgentChoiceImpactScanSkipped", version: 1

      attribute :scan_id, Types::Identifier
      attribute :decision_change, AgentChoiceImpacts::DecisionChangeEvidenceV1
      attribute :reason, Types::AgentChoiceImpactScanSkipReason
      attribute :policy_version, Types::AgentChoiceImpactPolicyVersion
      attribute :skipped_at, Types::Timestamp
    end
  end
end
