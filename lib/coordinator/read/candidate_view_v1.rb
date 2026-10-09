# frozen_string_literal: true

module Coordinator::Read
  class CandidateViewV1 < Value
    Intention = WorkIntentionViewV1

    attribute :candidate_id, Types::Identifier
    attribute :change_set_id, Types::Identifier
    attribute :work_item_id, Types::Identifier
    attribute :attempt_id, Types::Identifier
    attribute :agent_id, Types::Identifier
    attribute :repository_id, Types::RepositoryId
    attribute :target_branch, Types::CandidateTargetBranch
    attribute :object_format, Types::GitObjectFormat
    attribute :base_commit_oid, Types::GitOid
    attribute :head_commit_oid, Types::GitOid
    attribute :checkpoint_kind, Types::CandidateCheckpointKind
    attribute :intention_set_id, Types::UuidV7
    attribute :intention_policy_version, Types::WorkIntentionPolicyVersion
    attribute :intentions, Types::Array.of(Intention).constrained(min_size: 1, max_size: 32)
    attribute :manifest_digest, Types::Sha256Digest
    attribute :build_context_digest, Types::Sha256Digest.optional
    attribute :evidence_status, Types::CandidateEvidenceStatus
    attribute :submitted, CandidateSourceEvidenceV1
    attribute :manifest, CandidateManifestViewV1.optional
    attribute :build_context, CandidateBuildContextViewV1.optional
  end
end
