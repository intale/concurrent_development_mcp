# frozen_string_literal: true

module Coordinator::Write
  class WorkIntentionSetExpansionReceiptV1 < Value
    Reference = Types.Instance(LeaseReferenceV2)

    attribute :lease_set_id, Types::UuidV7
    attribute :repository_id, Types::RepositoryId
    attribute :policy_version, Types::String.enum(WorkIntentionPolicyV1::VERSION)
    attribute :expanded_at, Types::Timestamp
    attribute :expires_at, Types::Timestamp
    attribute :added_resources, Types::Array.of(Reference).constrained(max_size: 32)
    attribute :resource_count, Types::Integer.constrained(gteq: 1, lteq: 32)
  end
end
