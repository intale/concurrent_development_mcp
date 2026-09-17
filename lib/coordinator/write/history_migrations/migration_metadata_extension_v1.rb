# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class MigrationMetadataExtensionV1 < Value
      Collector = Types.Instance(Candidates::EvidenceCollectorV1) |
                  Types::DevelopmentArtifactCollector

      attribute? :attributed_actor, Commands::Actor.optional.default(nil)
      attribute? :canonical_input_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :policy_version,
                 Types::String.constrained(min_size: 1, max_size: 200).optional.default(nil)
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
      attribute? :snapshot_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :verification_input_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :verification_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :decision_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :expected_impact_policy,
                 MergeAuthorizations::ExpectedImpactPolicyV1.optional.default(nil)
      attribute? :input_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :authorization_decision_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :observation_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :policy,
                 CandidateObligations::ImpactPolicyEvidenceV1.optional.default(nil)
      attribute? :rule_version,
                 Types::String.constrained(min_size: 1, max_size: 200).optional.default(nil)
      attribute? :validity_input_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :assessment_input_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :obligation_validity_input_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :outcome_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :invalidated_policy,
                 CandidateObligations::ImpactPolicyEvidenceV1.optional.default(nil)
      attribute? :invalidation_digest, Types::Sha256Digest.optional.default(nil)
      attribute? :waiver_input_digest, Types::Sha256Digest.optional.default(nil)
    end
  end
end
