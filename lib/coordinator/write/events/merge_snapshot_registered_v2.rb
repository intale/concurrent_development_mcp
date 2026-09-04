# frozen_string_literal: true

module Coordinator::Write
  module Events
    class MergeSnapshotRegisteredV2 < Base
      contract type: "MergeSnapshotRegistered", version: 2

      attribute :merge_snapshot_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :target_branch, Types::CandidateTargetBranch
      attribute :object_format, Types::GitObjectFormat
      attribute :target_base_commit_oid, Types::GitOid
      attribute :merge_commit_oid, Types::GitOid
      attribute :ordered_candidates,
                Types::Array.of(Types::Identifier)
                  .constrained(min_size: 1, max_size: Types::MERGE_SNAPSHOT_MAXIMUM_CANDIDATES)
      attribute :producer, Types::Identifier
      attribute :run_id, Types::Identifier
      attribute :produced_at, Types::Timestamp
    end
  end
end
