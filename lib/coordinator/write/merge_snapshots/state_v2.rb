# frozen_string_literal: true

module Coordinator::Write
  module MergeSnapshots
    class StateV2 < Value
      Member = CandidateMemberV1

      attribute :merge_snapshot_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :target_branch, Types::CandidateTargetBranch
      attribute :object_format, Types::GitObjectFormat
      attribute :target_base_commit_oid, Types::GitOid
      attribute :merge_commit_oid, Types::GitOid
      attribute :ordered_candidates,
                Types::Array.of(Member)
                  .constrained(min_size: 1, max_size: Types::MERGE_SNAPSHOT_MAXIMUM_CANDIDATES)
      attribute :producer, Types::Identifier
      attribute :run_id, Types::Identifier
      attribute :produced_at, Types::Timestamp
      attribute :snapshot_digest, Types::Sha256Digest
      attribute :registration_event, EventReference
    end
  end
end
