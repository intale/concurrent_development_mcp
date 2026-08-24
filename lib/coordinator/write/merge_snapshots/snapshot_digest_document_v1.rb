# frozen_string_literal: true

module Coordinator::Write
  module MergeSnapshots
    class SnapshotDigestDocumentV1 < Value
      SCHEMA = "merge-snapshot-digest/v1"

      attribute :schema, Types::String.enum(SCHEMA)
      attribute :merge_snapshot_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :target_branch, Types::CandidateTargetBranch
      attribute :object_format, Types::GitObjectFormat
      attribute :target_base_commit_oid, Types::GitOid
      attribute :ordered_candidates,
                Types::Array.of(MemberDigestDocumentV1)
                  .constrained(min_size: 1, max_size: Types::MERGE_SNAPSHOT_MAXIMUM_CANDIDATES)
      attribute :merge_commit_oid, Types::GitOid
      attribute :producer, ProducerV1
      attribute :run_id, Types::Identifier
      attribute :produced_at, Types::Timestamp
      attribute :policy_version, Types::MergeSnapshotRegistrationPolicyVersion
    end
  end
end
