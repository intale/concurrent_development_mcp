# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class MigrationMetadataV1 < Value
      Collector = Types.Instance(Candidates::EvidenceCollectorV1) |
                  Types::DevelopmentArtifactCollector

      attribute :command_id, Types::UuidV7
      attribute :actor_kind, Types::ActorKind
      attribute :actor_id, Types::Identifier
      attribute :actor_authenticated, Types::Bool
      attribute :recorded_by, Types::String.enum("coordinator")
      attribute :policy_version, Types::String.constrained(min_size: 1, max_size: 200)
      attribute :migration_id, Types::UuidV7
      attribute :migration_source, MigrationSourceV1
      attribute? :canonical_input_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :collector, Collector.optional.default(nil)
      attribute? :encoding, Types::ContentEncoding.optional.default(nil)
      attribute? :media_type, Types::ContentMediaType.optional.default(nil)
      attribute? :byte_size, Types::ContentByteSize.optional.default(nil)
      attribute? :content_sha256, Types::Sha256Digest.optional.default(nil)
      attribute? :content_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :manifest_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :build_context_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :dependency_graph_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :test_environment_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :analyzer, Candidates::ImpactAnalyzerV1.optional.default(nil)
      attribute? :surface_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :marker_codec_version, Types::Identifier.optional.default(nil)
      attribute? :index_policy_version,
                 Types::CandidateImpactIndexPolicyVersion.optional.default(nil)
      attribute? :classifier,
                 Interpretations::ClassifierAttributionV1.optional.default(nil)
      attribute? :scope_provenance,
                 Interpretations::DecisionScopeProvenanceV1.optional.default(nil)
      attribute? :definition_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :context_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :before_context_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :after_context_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :previous_context_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :resulting_context_digest, Types::Sha256Digest.optional.default(nil)
    end
  end
end
