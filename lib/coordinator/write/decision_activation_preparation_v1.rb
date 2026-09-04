# frozen_string_literal: true

module Coordinator::Write
  class DecisionActivationPreparationV1 < Value
    attribute :activated_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
      attribute :recorded_event_id, Types::UuidV7
      attribute :derived_event_id, Types::UuidV7
      attribute :activated_event_id, Types::UuidV7
    attribute :slot_opened_event_id, Types::UuidV7
    attribute :slot_head_event_id, Types::UuidV7
    attribute :partition_event_ids, Types::Array.of(Types::UuidV7).constrained(size: 32)
  end
end
