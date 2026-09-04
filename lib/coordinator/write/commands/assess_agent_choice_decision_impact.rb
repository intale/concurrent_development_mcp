# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class AssessAgentChoiceDecisionImpact < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :assessment_id, Types::Identifier
      attribute :choice_id, Types::Identifier
      attribute :accepted_choice, EventReference
      attribute :decision_change, AgentChoiceImpacts::DecisionChangeEvidenceV2
      attribute :policy_version, Types::AgentChoiceImpactPolicyVersion
    end
  end
end
