# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CandidateBuildContextCapturedV1 < Base
      Input = Types.Instance(Candidates::BuildInputV1)
      Environment = Types.Instance(Candidates::EnvironmentEntryV1)

      contract type: "CandidateBuildContextCaptured", version: 1

      attribute :candidate_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :object_format, Types::GitObjectFormat
      attribute :head_commit_oid, Types::GitOid
      attribute :evidence_revision, Types::CandidateEvidenceRevision
      attribute :policy_version, Types::String.enum(Candidates::BuildContextDocumentV1::SCHEMA)
      attribute :build_context_digest, Types::Sha256Digest
      attribute :inputs, Types::Array.of(Input).constrained(max_size: 64)
      attribute :environment, Types::Array.of(Environment).constrained(max_size: 32)
      attribute :dependency_graph_digest, Types::Sha256Digest.optional
      attribute :test_environment_digest, Types::Sha256Digest.optional
      attribute :collector, Types.Instance(Candidates::EvidenceCollectorV1)
      attribute :captured_at, Types::Timestamp
    end
  end
end
