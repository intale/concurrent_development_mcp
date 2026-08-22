# frozen_string_literal: true

module Coordinator::Read
  class DecisionViewV1 < Value
    Partition = Coordinator::Write::Decisions::DecisionPartitionV1

    attribute :decision_id, Types::Identifier
    attribute :interpretation_id, Types::Identifier
    attribute :source_message_id, Types::Identifier
    attribute :policy_status, Types::DecisionPolicyStatus
    attribute :definition, Coordinator::Write::Decisions::DecisionDefinitionV1
    attribute :slot, Coordinator::Write::Decisions::DecisionSlotV1.optional
    attribute :partitions, Types::Array.of(Partition).constrained(max_size: 32)
    attribute :classifier, Coordinator::Write::Interpretations::ClassifierAttributionV1
    attribute :scope_provenance, Coordinator::Write::Interpretations::DecisionScopeProvenanceV1
    attribute :source_event, Coordinator::Write::EventReference
    attribute :proposal_event, Coordinator::Write::EventReference
    attribute :acceptance_event, Coordinator::Write::EventReference
    attribute :rationale, Coordinator::Write::Decisions::DecisionActivationRationaleV1.optional
    attribute :recorded, DecisionLifecycleEvidenceV1
    attribute :activated, DecisionLifecycleEvidenceV1.optional
  end
end
