# frozen_string_literal: true

module Coordinator::Write
  class PreparedWorkIntentionSetRenewal < Value
    Renewal = Types.Instance(PreparedWorkIntentionRenewalV1)

    attribute :renewed_at, Types::Timestamp
    attribute :expires_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :renewals, Types::Array.of(Renewal).constrained(min_size: 1, max_size: 32)
  end
end
