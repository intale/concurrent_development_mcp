# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ReleaseSetVerificationRecordedV1 < Base
      contract type: "ReleaseSetVerificationRecorded", version: 1

      attribute :release_set_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :release_digest, Types::Sha256Digest
      attribute :attempt_number, Types::ReleaseSetVerificationAttemptNumber
      attribute :integration_events,
                Types::Array.of(EventReference)
                  .constrained(
                    min_size: Types::RELEASE_SET_MINIMUM_MEMBERS,
                    max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS
                  )
      attribute :evidence, ReleaseSets::VerificationEvidenceV1
      attribute :verification_digest, Types::Sha256Digest
      attribute :policy_version, Types::ReleaseSetVerificationPolicyVersion
      attribute :evidence_status, Types::MergeSnapshotEvidenceStatus
      attribute :recorded_at, Types::Timestamp
    end
  end
end
