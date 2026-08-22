# frozen_string_literal: true

module Coordinator::Write
  module Decisions
    class DecisionCurrentStateV1 < Value
      Partition = Types.Instance(DecisionPartitionV1)

      attribute :decision_id, Types::Identifier
      attribute :definition, DecisionDefinitionV1
      attribute :head, DecisionHeadV1
      attribute :slot, DecisionSlotV1.optional
      attribute :partitions, Types::Array.of(Partition).constrained(min_size: 1, max_size: 32)
    end
  end
end
