# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class CandidateImpactV1Transformer
      include Dry::Monads[:result]

      def initialize(
        context_resolver:,
        stream_identity_allocator:,
        target_event_reference_resolver:,
        index_marker_builder:
      )
        @context_resolver = context_resolver
        @stream_identity_allocator = stream_identity_allocator
        @target_event_reference_resolver = target_event_reference_resolver
        @index_marker_builder = index_marker_builder
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        case source_payload
        when Events::CandidateImpactSurfaceDerivedV1
          transform_surface(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload
          )
        when Events::CandidateImpactSurfaceRegisteredV1
          transform_assignment(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload
          )
        end
      end

      private

      def transform_surface(migration_id:, source_config_name:, source_upper_position:, source_event:, source:)
        resolved = @context_resolver.from_stream(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:
        )
        return resolved if resolved.failure?

        context = resolved.value!
        unless surface_matches?(source, context.source_candidate)
          return Failure(inconsistent(source_event, "Candidate impact surface disagrees with its submission"))
        end

        allocation = @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_context: "DevelopmentIntegration",
          target_stream_name: "CandidateImpactSurface",
          identity_role: "candidate-impact-surface"
        )
        return allocation if allocation.failure?

        target_stream = allocation.value!.target_stream
        Success([
          TransformedFactV1.new(
            target_stream:,
            event: Events::CandidateImpactSurfaceDerivedV2.new(
              surface_id: target_stream.stream_id,
              candidate_id: context.candidate_id,
              evidence_revision: source.evidence_revision,
              produces: source.produces,
              consumes: source.consumes,
              may_affect: source.may_affect,
              assumes: source.assumes
            ),
            markers: context.markers,
            step_name: "derive-candidate-impact-surface",
            metadata_extension: MigrationMetadataExtensionV1.new(
              attributed_actor: actor_from(source_event),
              policy_version: source.policy_version,
              analyzer: source.analyzer,
              manifest_digest: source.manifest_digest,
              build_context_digest: source.build_context_digest,
              surface_digest: source.surface_digest
            )
          )
        ])
      end

      def transform_assignment(migration_id:, source_config_name:, source_upper_position:, source_event:, source:)
        resolved = @context_resolver.from_reference(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: source.candidate_event
        )
        return resolved if resolved.failure?

        context = resolved.value!
        unless assignment_matches?(source, context.source_candidate)
          return Failure(inconsistent(source_event, "Candidate impact assignment disagrees with its submission"))
        end

        evidence = load_evidence(source_event:, source_upper_position:, source:)
        return evidence if evidence.failure?

        manifest, build_context, surface = evidence.value!
        unless evidence_matches?(source, context.source_candidate, manifest, build_context, surface)
          return Failure(inconsistent(source_event, "Candidate impact assignment references inconsistent evidence"))
        end

        target_references = resolve_target_evidence(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source:
        )
        return target_references if target_references.failure?

        surface_reference = target_references.value!.last
        markers = context.markers + @index_marker_builder.call_documents(
          repository_id: context.repository_id,
          manifest:,
          build_context:,
          surface:
        )
        Success([
          TransformedFactV1.new(
            target_stream: context.candidate_stream,
            event: Events::CandidateImpactSurfaceAssignedV1.new(
              candidate_id: context.candidate_id,
              surface_id: surface_reference.stream_id
            ),
            markers:,
            step_name: "assign-candidate-impact-surface",
            metadata_extension: MigrationMetadataExtensionV1.new(
              attributed_actor: actor_from(source_event)
            )
          )
        ])
      end

      def load_evidence(source_event:, source_upper_position:, source:)
        manifest = @context_resolver.load_reference(
          source_event:,
          source_upper_position:,
          source_reference: source.manifest_event
        )
        return manifest if manifest.failure?

        build_context = load_optional_reference(
          source_event:,
          source_upper_position:,
          source_reference: source.build_context_event
        )
        return build_context if build_context.failure?

        surface = @context_resolver.load_reference(
          source_event:,
          source_upper_position:,
          source_reference: source.surface_event
        )
        return surface if surface.failure?

        manifest_payload = manifest.value!.payload
        build_context_payload = build_context.value!
        surface_payload = surface.value!.payload
        unless manifest_payload.is_a?(Events::CandidateChangeManifestCapturedV1) &&
            (build_context_payload.nil? || build_context_payload.is_a?(Events::CandidateBuildContextCapturedV1)) &&
            surface_payload.is_a?(Events::CandidateImpactSurfaceDerivedV1)
          return Failure(inconsistent(source_event, "Candidate impact references unexpected event contracts"))
        end

        Success([ manifest_payload, build_context_payload, surface_payload ])
      end

      def load_optional_reference(source_event:, source_upper_position:, source_reference:)
        return Success(nil) unless source_reference

        loaded = @context_resolver.load_reference(
          source_event:,
          source_upper_position:,
          source_reference:
        )
        return loaded if loaded.failure?

        Success(loaded.value!.payload)
      end

      def resolve_target_evidence(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:
      )
        manifest = resolve_target_reference(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: source.manifest_event,
          target_stream_name: "Candidate",
          identity_role: "candidate",
          target_event_type: "CandidateChangeManifestCaptured",
          target_step_name: "capture-candidate-change-manifest"
        )
        return manifest if manifest.failure?

        build_context = resolve_optional_target_reference(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: source.build_context_event
        )
        return build_context if build_context.failure?

        surface = resolve_target_reference(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: source.surface_event,
          target_stream_name: "CandidateImpactSurface",
          identity_role: "candidate-impact-surface",
          target_event_type: "CandidateImpactSurfaceDerived",
          target_step_name: "derive-candidate-impact-surface"
        )
        return surface if surface.failure?

        Success([ manifest.value!, build_context.value!, surface.value! ])
      end

      def resolve_optional_target_reference(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_reference:
      )
        return Success(nil) unless source_reference

        resolve_target_reference(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference:,
          target_stream_name: "Candidate",
          identity_role: "candidate",
          target_event_type: "CandidateBuildContextCaptured",
          target_step_name: "capture-candidate-build-context"
        )
      end

      def resolve_target_reference(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_reference:,
        target_stream_name:,
        identity_role:,
        target_event_type:,
        target_step_name:
      )
        @target_event_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference:,
          target_stream_context: "DevelopmentIntegration",
          target_stream_name:,
          identity_role:,
          target_event_type:,
          target_step_name:
        )
      end

      def assignment_matches?(assignment, candidate)
        [
          assignment.candidate_id,
          assignment.change_set_id,
          assignment.work_item_id,
          assignment.attempt_id,
          assignment.repository_id,
          assignment.target_branch,
          assignment.object_format,
          assignment.base_commit_oid,
          assignment.head_commit_oid
        ] == [
          candidate.candidate_id,
          candidate.change_set_id,
          candidate.work_item_id,
          candidate.attempt_id,
          candidate.repository_id,
          candidate.target_branch,
          candidate.object_format,
          candidate.base_commit_oid,
          candidate.head_commit_oid
        ]
      end

      def evidence_matches?(assignment, candidate, manifest, build_context, surface)
        manifest_matches?(manifest, candidate) &&
          build_context_matches?(build_context, candidate) &&
          surface_matches?(surface, candidate) &&
          assignment.surface_digest == surface.surface_digest
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
        return candidate.build_context_digest.nil? unless build_context

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

      def surface_matches?(surface, candidate)
        [
          surface.candidate_id,
          surface.change_set_id,
          surface.work_item_id,
          surface.attempt_id,
          surface.repository_id,
          surface.target_branch,
          surface.object_format,
          surface.head_commit_oid,
          surface.manifest_digest,
          surface.build_context_digest
        ] == [
          candidate.candidate_id,
          candidate.change_set_id,
          candidate.work_item_id,
          candidate.attempt_id,
          candidate.repository_id,
          candidate.target_branch,
          candidate.object_format,
          candidate.head_commit_oid,
          candidate.manifest_digest,
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
