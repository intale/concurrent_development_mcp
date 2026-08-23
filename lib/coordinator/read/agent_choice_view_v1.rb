# frozen_string_literal: true

module Coordinator::Read
  class AgentChoiceViewV1 < Value
    Option = Coordinator::Write::AgentChoices::ChoiceOptionV1

    attribute :choice_id, Types::Identifier
    attribute :choice_type, Types::AgentChoiceType
    attribute :observation_status, Types::AgentChoiceObservationStatus
    attribute :selected, Option
    attribute :alternatives, Types::Array.of(Option).constrained(max_size: 10)
    attribute :reason_summary, Types::String.constrained(min_size: 1, max_size: 1_000)
    attribute :context, Coordinator::Write::DecisionContexts::QueryContextV1
    attribute :decision_context, Coordinator::Write::DecisionContexts::ContextV1
    attribute :context_digest, Types::Sha256Digest
    attribute :assessment, Coordinator::Write::AgentChoices::ChoiceAssessmentV1.optional
    attribute :recorded, AgentChoiceLifecycleEvidenceV1
    attribute :accepted, AgentChoiceLifecycleEvidenceV1.optional
    attribute :invalidation, AgentChoiceInvalidationViewV1.optional
  end
end
