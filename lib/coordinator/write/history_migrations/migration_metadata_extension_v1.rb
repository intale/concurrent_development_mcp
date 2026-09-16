# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class MigrationMetadataExtensionV1 < Value
      attribute? :attributed_actor, Commands::Actor.optional.default(nil)
      attribute? :canonical_input_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :policy_version,
                 Types::String.constrained(min_size: 1, max_size: 200).optional.default(nil)
      attribute? :collector, Candidates::EvidenceCollectorV1.optional.default(nil)
      attribute? :manifest_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :build_context_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :dependency_graph_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :test_environment_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :analyzer, Candidates::ImpactAnalyzerV1.optional.default(nil)
      attribute? :surface_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :marker_codec_version, Types::Identifier.optional.default(nil)
      attribute? :index_policy_version,
                 Types::CandidateImpactIndexPolicyVersion.optional.default(nil)
    end
  end
end
