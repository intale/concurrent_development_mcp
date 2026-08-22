# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DecisionDefinitionCorrectedV1 < Base
      contract type: "DecisionDefinitionCorrected", version: 1

      Partition = Decisions::DecisionPartitionV1

      attribute :decision_id, Types::Identifier
      attribute :interpretation_id, Types::Identifier
      attribute :source_message_id, Types::Identifier
      attribute :source_event, EventReference
      attribute :proposal_event, EventReference
      attribute :acceptance_event, EventReference
      attribute :previous_head, Decisions::DecisionHeadV1
      attribute :previous_definition_digest, Types::Sha256Digest
      attribute :definition, Decisions::DecisionDefinitionV1
      attribute :classifier, Interpretations::ClassifierAttributionV1
      attribute :scope_provenance, Interpretations::DecisionScopeProvenanceV1
      attribute :previous_slot, Decisions::DecisionSlotV1.optional
      attribute :slot, Decisions::DecisionSlotV1.optional
      attribute :previous_partitions, Types::Array.of(Partition).constrained(min_size: 1, max_size: 32)
      attribute :partitions, Types::Array.of(Partition).constrained(min_size: 1, max_size: 32)
      attribute :rationale, Decisions::DecisionCorrectionRationaleV1
      attribute :corrected_at, Types::Timestamp
    end
  end
end
