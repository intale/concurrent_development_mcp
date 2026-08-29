# frozen_string_literal: true

module Coordinator::Write
  module Events
    class WriteSetReservedV2 < Base
      Reference = LeaseReferenceV2

      contract type: "WriteSetReserved", version: 2

      attribute :lease_set_id, Types::UuidV7
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :policy_version, Types::String.enum(LeaseResourceV2::POLICY_VERSION)
      attribute :resources, Types::Array.of(Reference).constrained(min_size: 1, max_size: 32)
      attribute :reserved_at, Types::Timestamp
      attribute :expires_at, Types::Timestamp
    end
  end
end
