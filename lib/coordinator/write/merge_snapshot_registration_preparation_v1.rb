# frozen_string_literal: true

module Coordinator::Write
  class MergeSnapshotRegistrationPreparationV1 < Value
    attribute :registered_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :commit_identity, MergeSnapshots::CommitIdentityV1
    attribute :snapshot_event_id, Types::UuidV7
    attribute :commit_registration_event_id, Types::UuidV7
    attribute :completion_event_id, Types::UuidV7
    attribute :correlation_id, Types::UuidV7
  end
end
