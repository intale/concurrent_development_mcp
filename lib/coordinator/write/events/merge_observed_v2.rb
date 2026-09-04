# frozen_string_literal: true

module Coordinator::Write
  module Events
    class MergeObservedV2 < Base
      contract type: "MergeObserved", version: 2

      attribute :merge_snapshot_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :target_branch, Types::CandidateTargetBranch
      attribute :object_format, Types::GitObjectFormat
      attribute :target_before_commit_oid, Types::GitOid
      attribute :target_after_commit_oid, Types::GitOid
      attribute :observer, Types::Identifier
      attribute :run_id, Types::Identifier
      attribute :snapshot_binding, MergeAuthorizations::SnapshotBindingV1
      attribute :observed_at, Types::Timestamp
    end
  end
end
