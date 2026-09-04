# frozen_string_literal: true

module Coordinator::Read
  class CandidateSubmissionViewV2 < Value
    Lease = Coordinator::Write::LeaseReferenceV2

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
    attribute :lease_references, Types::Array.of(Lease).constrained(min_size: 1, max_size: 32)
    attribute :manifest_digest, Types::Sha256Digest
    attribute :build_context_digest, Types::Sha256Digest.optional
    attribute :evidence_status, Types::CandidateEvidenceStatus
    attribute :manifest, Coordinator::Write::Events::CandidateChangeManifestCapturedV2
    attribute :build_context, Coordinator::Write::Events::CandidateBuildContextCapturedV2.optional
    attribute :submitted_event, Types.Instance(PgEventstore::Event)
    attribute :manifest_event, Types.Instance(PgEventstore::Event)
    attribute :build_context_event, Types.Instance(PgEventstore::Event).optional
  end
end
