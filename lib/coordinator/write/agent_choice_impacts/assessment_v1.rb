# frozen_string_literal: true

module Coordinator::Write
  module AgentChoiceImpacts
    class AssessmentV1 < Value
      Evaluation = AgentChoices::PolicyEvaluationV1
      Advancement = EventReference

      attribute :policy_version, Types::AgentChoiceImpactPolicyVersion
      attribute :before_context_digest, Types::Sha256Digest
      attribute :after_context_digest, Types::Sha256Digest
      attribute :before_evaluation, Evaluation
      attribute :after_evaluation, Evaluation
      attribute :source_advancements,
                Types::Array.of(Advancement).constrained(min_size: 1, max_size: 5)
      attribute :outcome, Types::AgentChoiceImpactAssessmentOutcome
      attribute :reason, Types::AgentChoiceImpactAssessmentReason
    end
  end
end
