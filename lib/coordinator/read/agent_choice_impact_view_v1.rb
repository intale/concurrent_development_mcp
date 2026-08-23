# frozen_string_literal: true

module Coordinator::Read
  class AgentChoiceImpactViewV1 < Value
    Evaluation = Coordinator::Write::AgentChoices::PolicyEvaluationV1

    attribute :assessment_id, Types::Identifier
    attribute :choice_id, Types::Identifier
    attribute :attempt_id, Types::Identifier
    attribute :outcome, Types::AgentChoiceImpactAssessmentOutcome
    attribute :reason, Types::AgentChoiceImpactAssessmentReason
    attribute :policy_version, Types::AgentChoiceImpactPolicyVersion
    attribute :accepted_choice, Coordinator::Write::EventReference
    attribute :decision_change, Coordinator::Write::AgentChoiceImpacts::DecisionChangeEvidenceV1
    attribute :before_context_digest, Types::Sha256Digest
    attribute :after_context_digest, Types::Sha256Digest
    attribute :before_evaluation, Evaluation
    attribute :after_evaluation, Evaluation
    attribute :source_advancements,
              Types::Array.of(Coordinator::Write::EventReference).constrained(min_size: 1, max_size: 5)
    attribute :source_actor, AttributedActorV1
    attribute :assessment_evidence, AgentChoiceImpactAssessmentEvidenceV1
  end
end
