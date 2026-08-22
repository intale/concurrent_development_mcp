# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Decisions
      class CorrectionState < Value
        SlotState = Coordinator::Write::Decisions::DecisionSlotStateV1
        PartitionState = Coordinator::Write::Decisions::DecisionPartitionStateV1

        attribute :current, Coordinator::Write::Decisions::DecisionCurrentStateV1
        attribute :candidate, Coordinator::Write::Decisions::DecisionCorrectionCandidateV1
        attribute :slot_states, Types::Array.of(SlotState).constrained(max_size: 2)
        attribute :partition_states, Types::Array.of(PartitionState).constrained(min_size: 1, max_size: 32)
      end
    end
  end
end
