# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DecisionActivatedV1 < Base
      contract type: "DecisionActivated", version: 1

      Partition = Decisions::DecisionPartitionV1

      attribute :decision_id, Types::Identifier
      attribute :interpretation_id, Types::Identifier
      attribute :recorded_event, EventReference
      attribute :definition_digest, Types::Sha256Digest
      attribute :slot, Decisions::DecisionSlotV1.optional
      attribute :partitions, Types::Array.of(Partition).constrained(min_size: 1, max_size: 32)
      attribute :rationale, Decisions::DecisionActivationRationaleV1
      attribute :activated_at, Types::Timestamp
    end
  end
end
