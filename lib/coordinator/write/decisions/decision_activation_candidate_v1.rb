# frozen_string_literal: true

module Coordinator::Write
  module Decisions
    class DecisionActivationCandidateV1 < Value
      Partition = Types.Instance(DecisionPartitionV1)

      attribute :proposal, Interpretations::InterpretationProposalEvidenceV1
      attribute :acceptance, InterpretationAcceptanceEvidenceV1
      attribute :definition, DecisionDefinitionV1
      attribute :slot, DecisionSlotV1.optional
      attribute :partitions, Types::Array.of(Partition).constrained(min_size: 1, max_size: 32)
      attribute :recorded_event, EventReference
      attribute :activated_event, EventReference
    end
  end
end
