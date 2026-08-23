# frozen_string_literal: true

module Coordinator::Read
  class CandidateManifestViewV1 < Value
    File = Coordinator::Write::Candidates::ManifestFileV1

    attribute :policy_version,
              Types::String.enum(Coordinator::Write::Candidates::ChangeManifestDocumentV1::SCHEMA)
    attribute :digest, Types::Sha256Digest
    attribute :files, Types::Array.of(File).constrained(min_size: 1, max_size: 256)
    attribute :collector, Coordinator::Write::Candidates::EvidenceCollectorV1
    attribute :evidence, CandidateSourceEvidenceV1
  end
end
