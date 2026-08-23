# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class ChangeManifestDocumentV1 < Value
      SCHEMA = "candidate-change-manifest/v1"
      File = Types.Instance(ManifestFileV1)

      attribute :schema, Types::String.enum(SCHEMA)
      attribute :candidate_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :target_branch, Types::CandidateTargetBranch
      attribute :object_format, Types::GitObjectFormat
      attribute :base_commit_oid, Types::GitOid
      attribute :head_commit_oid, Types::GitOid
      attribute :files, Types::Array.of(File).constrained(min_size: 1, max_size: 256)
    end
  end
end
