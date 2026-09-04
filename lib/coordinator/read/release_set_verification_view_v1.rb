# frozen_string_literal: true

module Coordinator::Read
  class ReleaseSetVerificationViewV1 < Value
    attribute :attempt_number, Types::ReleaseSetVerificationAttemptNumber
    attribute :integration_events,
              Types::Array.of(Coordinator::Write::EventReference)
                .constrained(max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS)
    attribute :evidence, Coordinator::Write::ReleaseSets::VerificationEvidenceV2
    attribute :verification_digest, Types::Sha256Digest
    attribute :policy_version, Types::ReleaseSetVerificationPolicyVersion
    attribute :evidence_status, Types::MergeSnapshotEvidenceStatus
    attribute :recorded_at, Types::Timestamp
    attribute :source, ReleaseSetSourceEvidenceV1
  end
end
