# frozen_string_literal: true

module Coordinator::Read
  class CandidateSummaryV1 < Value
    attribute :candidate_id, Types::Identifier
    attribute :change_set_id, Types::Identifier
    attribute :work_item_id, Types::Identifier
    attribute :attempt_id, Types::Identifier
    attribute :repository_id, Types::RepositoryId
    attribute :target_branch, Types::CandidateTargetBranch
    attribute :object_format, Types::GitObjectFormat
    attribute :base_commit_oid, Types::GitOid
    attribute :head_commit_oid, Types::GitOid
    attribute :checkpoint_kind, Types::CandidateCheckpointKind
    attribute :manifest_digest, Types::Sha256Digest
    attribute :build_context_digest, Types::Sha256Digest.optional
    attribute :evidence_status, Types::CandidateEvidenceStatus
    attribute :manifest_observed, Types::Bool
    attribute :build_context_observed, Types::Bool
    attribute :submitted, CandidateSourceEvidenceV1
  end
end
