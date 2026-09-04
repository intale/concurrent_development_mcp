# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class CandidateBuildContextV2 < EventMetadata
      attribute :collector, Candidates::EvidenceCollectorV1
      attribute :build_context_digest, Types::Sha256Digest
      attribute :dependency_graph_digest, Types::Sha256Digest.optional
      attribute :test_environment_digest, Types::Sha256Digest.optional
    end
  end
end
