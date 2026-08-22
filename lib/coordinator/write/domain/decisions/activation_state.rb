# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Decisions
      class ActivationState < Value
        PartitionState = Coordinator::Write::Decisions::DecisionPartitionStateV1

        attribute :candidate, Coordinator::Write::Decisions::DecisionActivationCandidateV1
        attribute :existing_decision, EventReference.optional
        attribute :existing_activation, Coordinator::Write::Decisions::DecisionActivationEvidenceV1.optional
        attribute :slot_head, Coordinator::Write::Decisions::DecisionHeadV1.optional
        attribute :partition_states, Types::Array.of(PartitionState).constrained(min_size: 1, max_size: 32)
      end
    end
  end
end
