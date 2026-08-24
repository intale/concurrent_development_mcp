# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class RequestedMemberV1 < Value
      attribute :repository_id, Types::RepositoryId
      attribute :target_branch, Types::CandidateTargetBranch
      attribute :object_format, Types::GitObjectFormat
      attribute :merge_snapshot_id, Types::Identifier
      attribute :snapshot_binding, MergeAuthorizations::SnapshotBindingV1
      attribute :authorization_event, EventReference
      attribute :authorization_decision_digest, Types::Sha256Digest
    end
  end
end
