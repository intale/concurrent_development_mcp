# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class StateV2 < Value
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
      attribute :manifest_digest, Types::Sha256Digest
      attribute :build_context_digest, Types::Sha256Digest.optional
      attribute :manifest, Events::CandidateChangeManifestCapturedV2
      attribute :build_context, Events::CandidateBuildContextCapturedV2.optional
      attribute :submission_event, EventReference
      attribute :manifest_event, EventReference
      attribute :build_context_event, EventReference.optional
      attribute :surface_id, Types::UuidV7.optional
      attribute :surface_assignment_event, EventReference.optional
      attribute :latest_revision, Types::Integer.constrained(gteq: 0)

      def evidence_status
        "attributed_unverified"
      end
    end
  end
end
