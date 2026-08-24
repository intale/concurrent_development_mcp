# frozen_string_literal: true

module Coordinator::Write
  module MergeSnapshotVerifications
    class BindingV1 < Value
      Candidate = BindingCandidateV1

      attribute :snapshot_event, EventReference
      attribute :snapshot_digest, Types::Sha256Digest
      attribute :repository_id, Types::RepositoryId
      attribute :target_branch, Types::CandidateTargetBranch
      attribute :object_format, Types::GitObjectFormat
      attribute :target_base_commit_oid, Types::GitOid
      attribute :ordered_candidates,
                Types::Array.of(Candidate)
                  .constrained(min_size: 1, max_size: Types::MERGE_SNAPSHOT_MAXIMUM_CANDIDATES)
      attribute :merge_commit_oid, Types::GitOid
    end
  end
end
