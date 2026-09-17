# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class MergeSnapshotVerificationV1Transformer
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        context_resolver:,
        stream_identity_allocator:,
        target_event_reference_resolver:,
        schema_registry: LegacyEventSchemaRegistry.new
      )
        @event_store = event_store
        @context_resolver = context_resolver
        @stream_identity_allocator = stream_identity_allocator
        @target_event_reference_resolver = target_event_reference_resolver
        @schema_registry = schema_registry
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        case source_payload
        when Events::MergeSnapshotVerificationSubmittedV1
          transform_submission(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload
          )
        when Events::MergeSnapshotVerifiedV1
          transform_verification(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload
          )
        end
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      private

      def transform_submission(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:
      )
        context_result = @context_resolver.from_reference(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: source.snapshot.event
        )
        return context_result if context_result.failure?

        context = context_result.value!
        validation = validate_submission(
          source_event:,
          source:,
          context:,
          source_upper_position:
        )
        return validation if validation.failure?

        allocation = @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_context: "DevelopmentIntegration",
          target_stream_name: "MergeVerification",
          identity_role: "merge-verification"
        )
        return allocation if allocation.failure?

        verification_stream = allocation.value!.target_stream
        verification_id = verification_stream.stream_id
        markers = context.markers + [
          "merge-snapshot-verification:#{verification_id}",
          "merge-snapshot-verification-policy:#{source.policy_version}",
          "verification-evidence-kind:#{source.assessment.evidence_kind}",
          "verification-evidence-conclusion:#{source.assessment.conclusion}"
        ]
        actor = actor_metadata(source_event)
        Success([
          fact(
            target_stream: verification_stream,
            event: Events::MergeSnapshotVerificationSubmittedV2.new(
              verification_id:,
              merge_snapshot_id: context.merge_snapshot_id,
              assessment: source.assessment
            ),
            markers:,
            step_name: "submit-merge-snapshot-verification",
            metadata_extension: actor_metadata(
              source_event,
              policy_version: source.policy_version,
              verification_input_digest: source.verification_input_digest
            )
          ),
          fact(
            target_stream: context.snapshot_stream,
            event: Events::MergeSnapshotVerificationAssignedV1.new(
              verification_id:,
              merge_snapshot_id: context.merge_snapshot_id
            ),
            markers:,
            step_name: "assign-merge-snapshot-verification",
            metadata_extension: actor
          )
        ])
      end

      def transform_verification(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:
      )
        context_result = @context_resolver.from_reference(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: source.snapshot.event
        )
        return context_result if context_result.failure?

        context = context_result.value!
        selected = load_reference(
          source_event:,
          source_upper_position:,
          source_reference: source.selected_verification.event
        )
        return selected if selected.failure?

        selected_event, selected_payload = selected.value!
        validation = validate_verification(
          source_event:,
          source:,
          context:,
          selected_event:,
          selected_payload:,
          source_upper_position:
        )
        return validation if validation.failure?

        target_submission = @target_event_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: source.selected_verification.event,
          target_stream_context: "DevelopmentIntegration",
          target_stream_name: "MergeVerification",
          identity_role: "merge-verification",
          target_event_type: "MergeSnapshotVerificationSubmitted",
          target_step_name: "submit-merge-snapshot-verification"
        )
        return target_submission if target_submission.failure?

        target_verification = target_submission.value!
        markers = context.markers + [
          "merge-snapshot-verification:#{target_verification.stream_id}",
          "merge-snapshot-verification-policy:#{source.policy_version}",
          "merge-snapshot-status:verified"
        ]
        actor = actor_metadata(source_event)
        Success([
          fact(
            target_stream: context.snapshot_stream,
            event: Events::MergeSnapshotVerificationSelectedV1.new(
              merge_snapshot_id: context.merge_snapshot_id,
              verification_id: target_verification.stream_id
            ),
            markers:,
            step_name: "select-merge-snapshot-verification",
            metadata_extension: actor
          ),
          fact(
            target_stream: context.snapshot_stream,
            event: Events::MergeSnapshotVerifiedV2.new(
              merge_snapshot_id: context.merge_snapshot_id
            ),
            markers:,
            step_name: "verify-merge-snapshot",
            metadata_extension: actor_metadata(
              source_event,
              policy_version: source.policy_version,
              verification_digest: source.verification_digest
            )
          )
        ])
      end

      def validate_submission(source_event:, source:, context:, source_upper_position:)
        stream = source_event.stream
        valid = source_event.type == "MergeSnapshotVerificationSubmitted" &&
                source_event.metadata.fetch("schema_version") == 1 &&
                source_event.global_position <= source_upper_position &&
                source_event.stream_revision.zero? &&
                stream.context == "DevelopmentIntegration" &&
                stream.stream_name == "MergeVerification" &&
                stream.stream_id == source.verification_id &&
                source.merge_snapshot_id == context.source_registration.merge_snapshot_id &&
                source_event.markers.include?("merge-snapshot:#{source.merge_snapshot_id}") &&
                snapshot_matches?(source.snapshot, context)
        return Success() if valid

        Failure(inconsistent(source_event, "merge snapshot verification submission is inconsistent"))
      end

      def validate_verification(
        source_event:,
        source:,
        context:,
        selected_event:,
        selected_payload:,
        source_upper_position:
      )
        stream = source_event.stream
        selected = source.selected_verification
        valid = source_event.type == "MergeSnapshotVerified" &&
                source_event.metadata.fetch("schema_version") == 1 &&
                source_event.global_position <= source_upper_position &&
                stream.context == "DevelopmentIntegration" &&
                stream.stream_name == "MergeSnapshot" &&
                stream.stream_id == source.merge_snapshot_id &&
                source.merge_snapshot_id == context.source_registration.merge_snapshot_id &&
                source_event.markers.include?("merge-snapshot:#{source.merge_snapshot_id}") &&
                snapshot_matches?(source.snapshot, context) &&
                selected_payload.is_a?(Events::MergeSnapshotVerificationSubmittedV1) &&
                selected_event.stream.context == "DevelopmentIntegration" &&
                selected_event.stream.stream_name == "MergeVerification" &&
                selected_event.stream.stream_id == selected.verification_id &&
                selected.verification_id == selected_payload.verification_id &&
                selected.evidence_kind == selected_payload.assessment.evidence_kind &&
                selected.conclusion == selected_payload.assessment.conclusion &&
                selected.result_digest == selected_payload.assessment.result_digest &&
                selected.verification_input_digest == selected_payload.verification_input_digest &&
                snapshot_matches?(selected_payload.snapshot, context)
        return Success() if valid

        Failure(inconsistent(source_event, "merge snapshot verification decision is inconsistent"))
      end

      def snapshot_matches?(evidence, context)
        evidence.event == context.source_registration_reference &&
          context.source_state_matches?(evidence.snapshot)
      end

      def load_reference(source_event:, source_upper_position:, source_reference:)
        event = @event_store.read_at(
          StreamReference.new(
            context: source_reference.stream_context,
            stream_name: source_reference.stream_name,
            stream_id: source_reference.stream_id
          ),
          source_reference.stream_revision
        )
        unless event && event.id == source_reference.event_id && event.type == source_reference.type &&
            event.global_position <= source_upper_position
          return Failure(inconsistent(source_event, "verification reference is absent from the frozen source range"))
        end

        Success([ event, load(event) ])
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def fact(target_stream:, event:, markers:, step_name:, metadata_extension:)
        TransformedFactV1.new(
          target_stream:,
          event:,
          markers:,
          step_name:,
          metadata_extension:
        )
      end

      def actor_metadata(source_event, **attributes)
        attributes[:policy_version] ||= source_event.metadata["policy_version"]
        MigrationMetadataExtensionV1.new(
          attributed_actor: Commands::Actor.new(
            kind: source_event.metadata.fetch("actor_kind"),
            id: source_event.metadata.fetch("actor_id")
          ),
          **attributes
        )
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Merge snapshot verification transformation is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
