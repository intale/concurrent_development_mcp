# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligations
    class CandidateSubjectV1 < Value
      attribute :candidate_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :target_branch, Types::CandidateTargetBranch
      attribute :object_format, Types::GitObjectFormat
      attribute :base_commit_oid, Types::GitOid
      attribute :head_commit_oid, Types::GitOid
      attribute :manifest_digest, Types::Sha256Digest
      attribute :build_context_digest, Types::Sha256Digest.optional
      attribute :surface_digest, Types::Sha256Digest
      attribute :candidate_event, EventReference
      attribute :manifest_event, EventReference
      attribute :build_context_event, EventReference.optional
      attribute :surface_event, EventReference
      attribute :registration_event, EventReference
    end
  end
end
