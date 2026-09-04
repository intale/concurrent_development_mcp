# frozen_string_literal: true

module Coordinator::Read
  class MergeObservationViewV1 < Value
    attribute :authorization_event, Coordinator::Write::EventReference
    attribute :authorization_decision_digest, Types::Sha256Digest
    attribute :snapshot_binding, Coordinator::Write::MergeAuthorizations::SnapshotBindingV1
    attribute :repository_id, Types::RepositoryId
    attribute :target_branch, Types::CandidateTargetBranch
    attribute :object_format, Types::GitObjectFormat
    attribute :target_before_commit_oid, Types::GitOid
    attribute :target_after_commit_oid, Types::GitOid
    attribute :observer, Types::Identifier
    attribute :run_id, Types::Identifier
    attribute :observed_at, Types::Timestamp
    attribute :observation_digest, Types::Sha256Digest
    attribute :policy_version, Types::MergeObservationPolicyVersion
    attribute :evidence_status, Types::MergeSnapshotEvidenceStatus
    attribute :recorded_at, Types::Timestamp
    attribute :source, MergeSnapshotSourceEvidenceV1
  end
end
