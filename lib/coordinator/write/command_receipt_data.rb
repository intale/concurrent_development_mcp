# frozen_string_literal: true

module Coordinator::Write
  module CommandReceiptData
    class ChangeSet < Value
      attribute :change_set_id, Types::Identifier
    end

    class WorkItem < Value
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
    end

    class Dependency < Value
      attribute :change_set_id, Types::Identifier
      attribute :dependency_id, Types::Identifier
    end

    class Attempt < Value
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
    end

    class LeaseSet < Value
      Reference = LeaseReferenceV1

      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :lease_set_id, Types::UuidV7
      attribute :policy_version, Types::String.enum(ResourceKeyDocumentV1::POLICY_VERSION)
      attribute :acquired_at, Types::Timestamp
      attribute :expires_at, Types::Timestamp
      attribute :resources, Types::Array.of(Reference).constrained(min_size: 1, max_size: 32)
    end

    class LeaseSetExpansion < Value
      Reference = LeaseReferenceV1

      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :lease_set_id, Types::UuidV7
      attribute :policy_version, Types::String.enum(ResourceKeyDocumentV1::POLICY_VERSION)
      attribute :expanded_at, Types::Timestamp
      attribute :expires_at, Types::Timestamp
      attribute :added_resources, Types::Array.of(Reference).constrained(min_size: 1, max_size: 31)
      attribute :resource_count, Types::ExpandedWriteSetSize
    end

    class LeaseSetRenewal < Value
      Reference = LeaseReferenceV1

      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :lease_set_id, Types::UuidV7
      attribute :policy_version, Types::String.enum(ResourceKeyDocumentV1::POLICY_VERSION)
      attribute :resources, Types::Array.of(Reference).constrained(min_size: 1, max_size: 32)
      attribute :resource_count, Types::WriteSetSize
      attribute :renewed_at, Types::Timestamp
      attribute :previous_expires_at, Types::Timestamp
      attribute :expires_at, Types::Timestamp
    end

    class LeaseSetRelease < Value
      Reference = LeaseReferenceV1

      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :lease_set_id, Types::UuidV7
      attribute :policy_version, Types::String.enum(ResourceKeyDocumentV1::POLICY_VERSION)
      attribute :resources, Types::Array.of(Reference).constrained(min_size: 1, max_size: 32)
      attribute :resource_count, Types::WriteSetSize
      attribute :previous_expires_at, Types::Timestamp
      attribute :released_at, Types::Timestamp
    end

    Type = ChangeSet | WorkItem | Dependency | Attempt | LeaseSet | LeaseSetExpansion | LeaseSetRenewal | LeaseSetRelease
  end
end
