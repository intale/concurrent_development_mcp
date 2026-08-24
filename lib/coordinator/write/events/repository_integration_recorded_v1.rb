# frozen_string_literal: true

module Coordinator::Write
  module Events
    class RepositoryIntegrationRecordedV1 < Base
      contract type: "RepositoryIntegrationRecorded", version: 1

      attribute :release_set_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :release_digest, Types::Sha256Digest
      attribute :repository_id, Types::RepositoryId
      attribute :member_position, Types::ReleaseSetMemberPosition
      attribute :attempt_id, Types::Identifier
      attribute :attempt_number, Types::ReleaseSetIntegrationAttemptNumber
      attribute :outcome, Types::ReleaseSetIntegrationOutcome
      attribute :merge_observation_event, EventReference.optional
      attribute :observation_digest, Types::Sha256Digest.optional
      attribute :failure, ReleaseSets::IntegrationFailureV1.optional
      attribute :integration_digest, Types::Sha256Digest
      attribute :policy_version, Types::ReleaseSetIntegrationPolicyVersion
      attribute :evidence_status, Types::MergeSnapshotEvidenceStatus
      attribute :recorded_at, Types::Timestamp
    end
  end
end
