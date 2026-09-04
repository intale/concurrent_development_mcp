# frozen_string_literal: true

module Coordinator::Write
  module AgentChoiceImpacts
    class ImpactAssessmentV2 < Value
      Evaluation = AgentChoices::PolicyEvaluationV1

      attribute :before_evaluation, Evaluation
      attribute :after_evaluation, Evaluation
      attribute :outcome, Types::AgentChoiceImpactAssessmentOutcome
      attribute :reason, Types::AgentChoiceImpactAssessmentReason
    end
  end
end
