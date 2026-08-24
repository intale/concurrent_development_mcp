# frozen_string_literal: true

module Coordinator::Read
  class ReleaseSetIntegrationViewV1 < Value
    attribute :repository_id, Types::RepositoryId
    attribute :member_position, Types::ReleaseSetMemberPosition
    attribute :attempt_id, Types::Identifier
    attribute :attempt_number, Types::ReleaseSetIntegrationAttemptNumber
    attribute :outcome, Types::ReleaseSetIntegrationOutcome
    attribute :merge_observation_event, Coordinator::Write::EventReference.optional
    attribute :observation_digest, Types::Sha256Digest.optional
    attribute :failure, Coordinator::Write::ReleaseSets::IntegrationFailureV1.optional
    attribute :integration_digest, Types::Sha256Digest
    attribute :policy_version, Types::ReleaseSetIntegrationPolicyVersion
    attribute :evidence_status, Types::MergeSnapshotEvidenceStatus
    attribute :recorded_at, Types::Timestamp
    attribute :source, ReleaseSetSourceEvidenceV1
  end
end
