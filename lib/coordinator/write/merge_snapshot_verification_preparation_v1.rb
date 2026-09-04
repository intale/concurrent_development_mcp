# frozen_string_literal: true

module Coordinator::Write
  class MergeSnapshotVerificationPreparationV1 < Value
    attribute :verification_id, Types::UuidV7
    attribute :submitted_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :submission_event_id, Types::UuidV7
    attribute :assignment_event_id, Types::UuidV7
    attribute :correlation_id, Types::UuidV7
  end
end
