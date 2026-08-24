# frozen_string_literal: true

module Coordinator::Write
  module Events
    class MergeSnapshotRegisteredV1 < Base
      Member = MergeSnapshots::CandidateMemberV1

      contract type: "MergeSnapshotRegistered", version: 1

      attribute :merge_snapshot_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :target_branch, Types::CandidateTargetBranch
      attribute :object_format, Types::GitObjectFormat
      attribute :target_base_commit_oid, Types::GitOid
      attribute :ordered_candidates,
                Types::Array.of(Member)
                  .constrained(min_size: 1, max_size: Types::MERGE_SNAPSHOT_MAXIMUM_CANDIDATES)
      attribute :merge_commit_oid, Types::GitOid
      attribute :producer, MergeSnapshots::ProducerV1
      attribute :run_id, Types::Identifier
      attribute :produced_at, Types::Timestamp
      attribute :snapshot_digest, Types::Sha256Digest
      attribute :policy_version, Types::MergeSnapshotRegistrationPolicyVersion
      attribute :evidence_status, Types::MergeSnapshotEvidenceStatus
      attribute :registered_at, Types::Timestamp
    end
  end
end
