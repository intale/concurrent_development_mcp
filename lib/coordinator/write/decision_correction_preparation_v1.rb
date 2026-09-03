# frozen_string_literal: true

module Coordinator::Write
  class DecisionCorrectionPreparationV1 < Value
    attribute :corrected_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :correction_event_id, Types::UuidV7
    attribute :slot_event_ids, Types::Array.of(Types::UuidV7).constrained(size: 3)
    attribute :partition_event_ids, Types::Array.of(Types::UuidV7).constrained(size: 32)
  end
end
