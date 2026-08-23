# frozen_string_literal: true

module Coordinator::Write
  module Events
    class AgentChoiceImpactAssessedV1 < Base
      contract type: "AgentChoiceImpactAssessed", version: 1

      attribute :assessment_id, Types::Identifier
      attribute :choice_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :accepted_choice, EventReference
      attribute :decision_change, AgentChoiceImpacts::DecisionChangeEvidenceV1
      attribute :assessment, AgentChoiceImpacts::AssessmentV1
      attribute :assessed_at, Types::Timestamp
    end
  end
end
