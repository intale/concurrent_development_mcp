# frozen_string_literal: true

module Coordinator::Read
  module CommandResults
    class WorkIntentionSetEvidenceV1 < Value
      Reference = Coordinator::Write::WorkIntentionReceiptReferenceV1

      attribute :set_id, Types::UuidV7
      attribute :repository_id, Types::RepositoryId
      attribute :resources,
                Types::Array.of(Reference)
                  .constrained(min_size: 1, max_size: Coordinator::Shared::Types::WRITE_SET_RESOURCE_MAXIMUM_COUNT)
      attribute :created_at, Types::Timestamp
      attribute :current_expires_at, Types::Timestamp
      attribute :before_command_expires_at, Types::Timestamp.optional
    end
  end
end
