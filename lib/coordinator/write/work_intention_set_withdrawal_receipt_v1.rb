# frozen_string_literal: true

module Coordinator::Write
  class WorkIntentionSetWithdrawalReceiptV1 < Value
    Reference = Types.Instance(WorkIntentionReceiptReferenceV1)

    attribute :intention_set_id, Types::UuidV7
    attribute :repository_id, Types::RepositoryId
    attribute :policy_version, Types::String.enum(WorkIntentionPolicyV1::VERSION)
    attribute :intentions, Types::Array.of(Reference).constrained(min_size: 1, max_size: 32)
    attribute :intention_count, Types::Integer.constrained(gteq: 1, lteq: 32)
    attribute :previous_expires_at, Types::Timestamp
    attribute :withdrawn_at, Types::Timestamp
  end
end
