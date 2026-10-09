# frozen_string_literal: true

module Coordinator::Write
  class PreparedWorkIntentionSetWithdrawal < Value
    Withdrawal = Types.Instance(PreparedWorkIntentionWithdrawalV1)

    attribute :withdrawn_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :withdrawals, Types::Array.of(Withdrawal).constrained(min_size: 1, max_size: 32)
  end
end
