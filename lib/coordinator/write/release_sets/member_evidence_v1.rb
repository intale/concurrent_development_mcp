# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class MemberEvidenceV1 < Value
      Candidate = MergeSnapshots::CandidateMemberV1

      attribute :position, Types::ReleaseSetMemberPosition
      attribute :repository_id, Types::RepositoryId
      attribute :target_branch, Types::CandidateTargetBranch
      attribute :object_format, Types::GitObjectFormat
      attribute :merge_snapshot_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :target_base_commit_oid, Types::GitOid
      attribute :merge_commit_oid, Types::GitOid
      attribute :snapshot_binding, MergeAuthorizations::SnapshotBindingV1
      attribute :authorization_event, EventReference
      attribute :authorization_decision_digest, Types::Sha256Digest
      attribute :ordered_candidates,
                Types::Array.of(Candidate)
                  .constrained(min_size: 1, max_size: Types::MERGE_SNAPSHOT_MAXIMUM_CANDIDATES)
    end
  end
end
