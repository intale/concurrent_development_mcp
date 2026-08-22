# frozen_string_literal: true

module Coordinator::Read
  class InterpretationProposalV1 < Value
    Ambiguity = Coordinator::Write::Interpretations::InterpretationAmbiguityV1

    attribute :interpretation_id, Types::Identifier
    attribute :message_id, Types::Identifier
    attribute :source_event, Coordinator::Write::EventReference
    attribute :source_span, Coordinator::Write::Interpretations::SourceSpanV1.optional
    attribute :classifier, Coordinator::Write::Interpretations::ClassifierAttributionV1
    attribute :proposed_decision, Coordinator::Write::Interpretations::ProposedDecisionV1
    attribute :scope_provenance, Coordinator::Write::Interpretations::DecisionScopeProvenanceV1
    attribute :ambiguities, Types::Array.of(Ambiguity).constrained(max_size: 20)
    attribute :assessment, Coordinator::Write::Interpretations::InterpretationAssessmentV1
    attribute :lifecycle_status, Types::InterpretationLifecycleStatus
    attribute :policy_status, Types::InterpretationPolicyStatus
    attribute :adjudication, InterpretationAdjudicationV1.optional
    attribute :actor, AttributedActorV1
    attribute :event, Coordinator::Write::EventReference
    attribute :clarification_event, Coordinator::Write::EventReference.optional
    attribute :proposed_at, Types::Timestamp
    attribute :clarification_required_at, Types::Timestamp.optional
    attribute :causation_id, Types::UuidV7.optional
    attribute :correlation_id, Types::UuidV7.optional
  end
end
