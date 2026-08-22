# frozen_string_literal: true

module Coordinator::Write
  class PreparedLeaseSetRenewal < Value
    Renewal = Types.Instance(PreparedLeaseRenewalV1)

    attribute :renewed_at, Types::Timestamp
    attribute :expires_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :renewals, Types::Array.of(Renewal).constrained(min_size: 1, max_size: 32)
    attribute :write_set_event_id, Types::UuidV7
    attribute :completion_event_id, Types::UuidV7
  end
end
