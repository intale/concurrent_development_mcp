# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class CandidateEvidenceV1Transformer
      include Dry::Monads[:result]

      def initialize(context_resolver:)
        @context_resolver = context_resolver
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        resolved = @context_resolver.from_stream(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:
        )
        return resolved if resolved.failure?

        context = resolved.value!
        case source_payload
        when Events::CandidateChangeManifestCapturedV1
          transform_manifest(source_event:, source: source_payload, context:)
        when Events::CandidateBuildContextCapturedV1
          transform_build_context(source_event:, source: source_payload, context:)
        end
      end

      private

      def transform_manifest(source_event:, source:, context:)
        unless manifest_matches?(source, context.source_candidate)
          return Failure(inconsistent(source_event, "Candidate manifest disagrees with its submission"))
        end

        Success([
          fact(
            context,
            Events::CandidateChangeManifestCapturedV2.new(
              candidate_id: context.candidate_id,
              evidence_revision: source.evidence_revision,
              files: source.files
            ),
            "capture-candidate-change-manifest",
            MigrationMetadataExtensionV1.new(
              attributed_actor: actor_from(source_event),
              policy_version: source.policy_version,
              collector: source.collector,
              manifest_digest: source.manifest_digest
            )
          )
        ])
      end

      def transform_build_context(source_event:, source:, context:)
        unless build_context_matches?(source, context.source_candidate)
          return Failure(inconsistent(source_event, "Candidate build context disagrees with its submission"))
        end

        Success([
          fact(
            context,
            Events::CandidateBuildContextCapturedV2.new(
              candidate_id: context.candidate_id,
              evidence_revision: source.evidence_revision,
              inputs: source.inputs,
              environment: source.environment
            ),
            "capture-candidate-build-context",
            MigrationMetadataExtensionV1.new(
              attributed_actor: actor_from(source_event),
              policy_version: source.policy_version,
              collector: source.collector,
              build_context_digest: source.build_context_digest,
              dependency_graph_digest: source.dependency_graph_digest,
              test_environment_digest: source.test_environment_digest
            )
          )
        ])
      end

      def fact(context, event, step_name, metadata_extension)
        TransformedFactV1.new(
          target_stream: context.candidate_stream,
          event:,
          markers: context.markers,
          step_name:,
          metadata_extension:
        )
      end

      def manifest_matches?(manifest, candidate)
        [
          manifest.candidate_id,
          manifest.repository_id,
          manifest.target_branch,
          manifest.object_format,
          manifest.base_commit_oid,
          manifest.head_commit_oid,
          manifest.manifest_digest
        ] == [
          candidate.candidate_id,
          candidate.repository_id,
          candidate.target_branch,
          candidate.object_format,
          candidate.base_commit_oid,
          candidate.head_commit_oid,
          candidate.manifest_digest
        ]
      end

      def build_context_matches?(build_context, candidate)
        [
          build_context.candidate_id,
          build_context.repository_id,
          build_context.object_format,
          build_context.head_commit_oid,
          build_context.build_context_digest
        ] == [
          candidate.candidate_id,
          candidate.repository_id,
          candidate.object_format,
          candidate.head_commit_oid,
          candidate.build_context_digest
        ]
      end

      def actor_from(source_event)
        Commands::Actor.new(
          kind: source_event.metadata.fetch("actor_kind"),
          id: source_event.metadata.fetch("actor_id")
        )
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message:,
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
