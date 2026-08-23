# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CandidateAttachedToAttemptV1 < Base
      contract type: "CandidateAttachedToAttempt", version: 1

      attribute :candidate_id, Types::Identifier
      attribute :candidate_event, EventReference
      attribute :repository_id, Types::RepositoryId
      attribute :target_branch, Types::CandidateTargetBranch
      attribute :object_format, Types::GitObjectFormat
      attribute :base_commit_oid, Types::GitOid
      attribute :head_commit_oid, Types::GitOid
      attribute :checkpoint_kind, Types::CandidateCheckpointKind
      attribute :manifest_digest, Types::Sha256Digest
      attribute :build_context_digest, Types::Sha256Digest.optional
      attribute :attached_at, Types::Timestamp
    end
  end
end
