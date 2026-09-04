# frozen_string_literal: true

module Coordinator::Write
  class WorkIntentionSetRenewalReceiptV1 < Value
    Reference = Types.Instance(LeaseReferenceV2)

    attribute :lease_set_id, Types::UuidV7
    attribute :repository_id, Types::RepositoryId
    attribute :policy_version, Types::String.enum(WorkIntentionPolicyV1::VERSION)
    attribute :resources, Types::Array.of(Reference).constrained(min_size: 1, max_size: 32)
    attribute :resource_count, Types::Integer.constrained(gteq: 1, lteq: 32)
    attribute :renewed_at, Types::Timestamp
    attribute :previous_expires_at, Types::Timestamp
    attribute :expires_at, Types::Timestamp
  end
end
