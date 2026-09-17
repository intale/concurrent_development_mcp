# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class CandidateSubjectV1Transformer
      include Dry::Monads[:result]

      def initialize(context_resolver:, target_event_reference_resolver:)
        @context_resolver = context_resolver
        @target_event_reference_resolver = target_event_reference_resolver
      end

      def call(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        subject:
      )
        context = @context_resolver.from_reference(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: subject.candidate_event
        )
        return context if context.failure?

        evidence = load_evidence(source_event:, source_upper_position:, subject:)
        return evidence if evidence.failure?

        manifest, build_context, surface, registration = evidence.value!
        candidate_context = context.value!
        unless valid_subject?(
          subject,
          candidate_context.source_candidate,
          manifest,
          build_context,
          surface,
          registration
        )
          return Failure(inconsistent(source_event, "Candidate subject disagrees with its authoritative evidence"))
        end

        references = target_references(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          subject:,
          context: candidate_context
        )
        return references if references.failure?

        Success(
          CandidateSubjectMigrationV1.new(
            source_subject: subject,
            target_subject: target_subject(subject, candidate_context, references.value!),
            context: candidate_context,
            manifest:,
            build_context:,
            surface:,
            registration:
          )
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      private

      def load_evidence(source_event:, source_upper_position:, subject:)
        manifest = load_reference(source_event:, source_upper_position:, reference: subject.manifest_event)
        return manifest if manifest.failure?

        build_context = load_optional_reference(
          source_event:,
          source_upper_position:,
          reference: subject.build_context_event
        )
        return build_context if build_context.failure?

        surface = load_reference(source_event:, source_upper_position:, reference: subject.surface_event)
        return surface if surface.failure?

        registration = load_reference(
          source_event:,
          source_upper_position:,
          reference: subject.registration_event
        )
        return registration if registration.failure?

        values = [ manifest.value!, build_context.value!, surface.value!, registration.value! ]
        valid = values[0].is_a?(Events::CandidateChangeManifestCapturedV1) &&
                (values[1].nil? || values[1].is_a?(Events::CandidateBuildContextCapturedV1)) &&
                values[2].is_a?(Events::CandidateImpactSurfaceDerivedV1) &&
                values[3].is_a?(Events::CandidateImpactSurfaceRegisteredV1)
        return Success(values) if valid

        Failure(inconsistent(source_event, "Candidate subject references unexpected event contracts"))
      end

      def load_reference(source_event:, source_upper_position:, reference:)
        loaded = @context_resolver.load_reference(
          source_event:,
          source_upper_position:,
          source_reference: reference
        )
        return loaded if loaded.failure?

        Success(loaded.value!.payload)
      end

      def load_optional_reference(source_event:, source_upper_position:, reference:)
        return Success(nil) unless reference

        load_reference(source_event:, source_upper_position:, reference:)
      end

      def target_references(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        subject:,
        context:
      )
        candidate = context.target_submission_event
        return Failure(inconsistent(source_event, "target Candidate submission reference is absent")) unless candidate

        manifest = in_candidate_stream(
          migration_id:,
          source_upper_position:,
          source_event:,
          source_reference: subject.manifest_event,
          target_stream: context.candidate_stream,
          target_event_type: "CandidateChangeManifestCaptured",
          target_step_name: "capture-candidate-change-manifest"
        )
        return manifest if manifest.failure?

        build_context = if subject.build_context_event
          in_candidate_stream(
            migration_id:,
            source_upper_position:,
            source_event:,
            source_reference: subject.build_context_event,
            target_stream: context.candidate_stream,
            target_event_type: "CandidateBuildContextCaptured",
            target_step_name: "capture-candidate-build-context"
          )
        else
          Success(nil)
        end
        return build_context if build_context.failure?

        surface = @target_event_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: subject.surface_event,
          target_stream_context: "DevelopmentIntegration",
          target_stream_name: "CandidateImpactSurface",
          identity_role: "candidate-impact-surface",
          target_event_type: "CandidateImpactSurfaceDerived",
          target_step_name: "derive-candidate-impact-surface"
        )
        return surface if surface.failure?

        registration = in_candidate_stream(
          migration_id:,
          source_upper_position:,
          source_event:,
          source_reference: subject.registration_event,
          target_stream: context.candidate_stream,
          target_event_type: "CandidateImpactSurfaceAssigned",
          target_step_name: "assign-candidate-impact-surface"
        )
        return registration if registration.failure?

        Success(
          {
            candidate_event: candidate,
            manifest_event: manifest.value!,
            build_context_event: build_context.value!,
            surface_event: surface.value!,
            registration_event: registration.value!
          }.freeze
        )
      end

      def in_candidate_stream(**arguments)
        @target_event_reference_resolver.call_in_stream(**arguments)
      end

      def target_subject(source, context, references)
        CandidateObligations::CandidateSubjectV1.new(
          source.to_h.merge(
            candidate_id: context.candidate_id,
            change_set_id: context.change_set_id,
            work_item_id: context.work_item_id,
            attempt_id: context.attempt_id,
            repository_id: context.repository_id,
            **references
          )
        )
      end

      def valid_subject?(subject, candidate, manifest, build_context, surface, registration)
        candidate_matches?(subject, candidate) &&
          manifest_matches?(subject, manifest) &&
          build_context_matches?(subject, build_context) &&
          surface_matches?(subject, surface) &&
          registration_matches?(subject, registration)
      end

      def candidate_matches?(subject, candidate)
        subject_values(subject).values_at(0..10) == [
          candidate.candidate_id,
          candidate.change_set_id,
          candidate.work_item_id,
          candidate.attempt_id,
          candidate.repository_id,
          candidate.target_branch,
          candidate.object_format,
          candidate.base_commit_oid,
          candidate.head_commit_oid,
          candidate.manifest_digest,
          candidate.build_context_digest
        ] && subject.candidate_event.stream_id == candidate.candidate_id
      end

      def manifest_matches?(subject, manifest)
        [
          manifest.candidate_id,
          manifest.repository_id,
          manifest.target_branch,
          manifest.object_format,
          manifest.base_commit_oid,
          manifest.head_commit_oid,
          manifest.manifest_digest
        ] == [
          subject.candidate_id,
          subject.repository_id,
          subject.target_branch,
          subject.object_format,
          subject.base_commit_oid,
          subject.head_commit_oid,
          subject.manifest_digest
        ]
      end

      def build_context_matches?(subject, build_context)
        return subject.build_context_digest.nil? && subject.build_context_event.nil? unless build_context

        [
          build_context.candidate_id,
          build_context.repository_id,
          build_context.object_format,
          build_context.head_commit_oid,
          build_context.build_context_digest
        ] == [
          subject.candidate_id,
          subject.repository_id,
          subject.object_format,
          subject.head_commit_oid,
          subject.build_context_digest
        ]
      end

      def surface_matches?(subject, surface)
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
          surface.build_context_digest,
          surface.surface_digest
        ] == subject_values(subject).values_at(0, 1, 2, 3, 4, 5, 6, 8, 9, 10, 11)
      end

      def registration_matches?(subject, registration)
        [
          registration.candidate_id,
          registration.change_set_id,
          registration.work_item_id,
          registration.attempt_id,
          registration.repository_id,
          registration.target_branch,
          registration.object_format,
          registration.base_commit_oid,
          registration.head_commit_oid,
          registration.candidate_event,
          registration.manifest_event,
          registration.build_context_event,
          registration.surface_event,
          registration.surface_digest
        ] == [
          *subject_values(subject).values_at(0, 1, 2, 3, 4, 5, 6, 7, 8),
          subject.candidate_event,
          subject.manifest_event,
          subject.build_context_event,
          subject.surface_event,
          subject.surface_digest
        ]
      end

      def subject_values(subject)
        [
          subject.candidate_id,
          subject.change_set_id,
          subject.work_item_id,
          subject.attempt_id,
          subject.repository_id,
          subject.target_branch,
          subject.object_format,
          subject.base_commit_oid,
          subject.head_commit_oid,
          subject.manifest_digest,
          subject.build_context_digest,
          subject.surface_digest
        ]
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Candidate subject migration is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
