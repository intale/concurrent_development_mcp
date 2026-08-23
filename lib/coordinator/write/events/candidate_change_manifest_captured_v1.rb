# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CandidateChangeManifestCapturedV1 < Base
      File = Types.Instance(Candidates::ManifestFileV1)

      contract type: "CandidateChangeManifestCaptured", version: 1

      attribute :candidate_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :target_branch, Types::CandidateTargetBranch
      attribute :object_format, Types::GitObjectFormat
      attribute :base_commit_oid, Types::GitOid
      attribute :head_commit_oid, Types::GitOid
      attribute :evidence_revision, Types::CandidateEvidenceRevision
      attribute :policy_version, Types::String.enum(Candidates::ChangeManifestDocumentV1::SCHEMA)
      attribute :manifest_digest, Types::Sha256Digest
      attribute :files, Types::Array.of(File).constrained(min_size: 1, max_size: 256)
      attribute :collector, Types.Instance(Candidates::EvidenceCollectorV1)
      attribute :captured_at, Types::Timestamp
    end
  end
end
