# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class SubmitCandidateImpactSurface < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :candidate_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :head_commit_oid, Types::GitOid
      attribute :manifest_digest, Types::Sha256Digest
      attribute :build_context_digest, Types::Sha256Digest.optional
      attribute :surface, Candidates::ImpactSurfaceV1
    end
  end
end
