# frozen_string_literal: true

module Coordinator::Write
  module AgentChoiceImpacts
    class AssessmentIdentityDocumentV1 < Value
      attribute :schema, Types::String.enum("agent-choice-impact-assessment-identity/v1")
      attribute :policy_version, Types::AgentChoiceImpactPolicyVersion
      attribute :accepted_choice, EventReference
      attribute :decision_change, EventReference
    end
  end
end
