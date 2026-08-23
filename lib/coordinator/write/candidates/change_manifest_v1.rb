# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class ChangeManifestV1 < Value
      File = Types.Instance(ManifestFileV1)

      attribute :policy_version, Types::String.enum(ChangeManifestDocumentV1::SCHEMA)
      attribute :digest, Types::Sha256Digest
      attribute :files, Types::Array.of(File).constrained(min_size: 1, max_size: 256)
      attribute :collector, Types.Instance(EvidenceCollectorV1)
    end
  end
end
