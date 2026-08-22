# frozen_string_literal: true

module Coordinator::Write
  module Events
    class WriteSetExpandedV1 < Base
      Reference = LeaseReferenceV1

      contract type: "WriteSetExpanded", version: 1

      attribute :lease_set_id, Types::UuidV7
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :policy_version, Types::String.enum(ResourceKeyDocumentV1::POLICY_VERSION)
      attribute :added_resources, Types::Array.of(Reference).constrained(min_size: 1, max_size: 31)
      attribute :resource_count, Types::ExpandedWriteSetSize
      attribute :expanded_at, Types::Timestamp
      attribute :expires_at, Types::Timestamp
    end
  end
end
