# frozen_string_literal: true

module Coordinator::Write
  class WorkIntentionSetReceiptV1 < Value
    Reference = Types.Instance(LeaseReferenceV2)

    attribute :lease_set_id, Types::UuidV7
    attribute :repository_id, Types::RepositoryId
    attribute :policy_version, Types::String.enum(WorkIntentionPolicyV1::VERSION)
    attribute :reserved_at, Types::Timestamp
    attribute :expires_at, Types::Timestamp
    attribute :resources, Types::Array.of(Reference).constrained(min_size: 1, max_size: 32)
  end
end
