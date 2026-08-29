# frozen_string_literal: true

module Coordinator::Write
  class PreparedWriteSetReservation < Value
    Resource = Types.Instance(PreparedLeaseTargetV1)

    attribute :acquired_at, Types::Timestamp
    attribute :expires_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :lease_set_id, Types::UuidV7
    attribute :resources, Types::Array.of(Resource).constrained(min_size: 1, max_size: 32)
    attribute :reservation_event_id, Types::UuidV7
    attribute :completion_event_id, Types::UuidV7
  end
end
