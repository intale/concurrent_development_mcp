# frozen_string_literal: true

module Coordinator::Read
  class CandidateBuildContextViewV1 < Value
    Input = Coordinator::Write::Candidates::BuildInputV1
    Environment = Coordinator::Write::Candidates::EnvironmentEntryV1

    attribute :policy_version,
              Types::String.enum(Coordinator::Write::Candidates::BuildContextDocumentV1::SCHEMA)
    attribute :digest, Types::Sha256Digest
    attribute :inputs, Types::Array.of(Input).constrained(max_size: 64)
    attribute :environment, Types::Array.of(Environment).constrained(max_size: 32)
    attribute :dependency_graph_digest, Types::Sha256Digest.optional
    attribute :test_environment_digest, Types::Sha256Digest.optional
    attribute :collector, Coordinator::Write::Candidates::EvidenceCollectorV1
    attribute :evidence, CandidateSourceEvidenceV1
  end
end
