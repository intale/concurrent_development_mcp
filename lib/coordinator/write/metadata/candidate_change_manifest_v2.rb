# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class CandidateChangeManifestV2 < EventMetadata
      attribute :collector, Candidates::EvidenceCollectorV1
      attribute :manifest_digest, Types::Sha256Digest
    end
  end
end
