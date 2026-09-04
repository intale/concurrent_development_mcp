# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class CandidateImpactSurfaceV2 < EventMetadata
      attribute :analyzer, Candidates::ImpactAnalyzerV1
      attribute :manifest_digest, Types::Sha256Digest
      attribute :build_context_digest, Types::Sha256Digest.optional
      attribute :surface_digest, Types::Sha256Digest
    end
  end
end
