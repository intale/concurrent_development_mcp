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
    attribute :decision_change, Coordinator::Write::AgentChoiceImpacts::DecisionChangeEvidenceV2
    attribute :decision_changed_at, Types::Timestamp
    attribute :before_evaluation, Evaluation
    attribute :after_evaluation, Evaluation
    attribute :source_actor, AttributedActorV1
    attribute :assessment_evidence, AgentChoiceImpactAssessmentEvidenceV1
  end
end
