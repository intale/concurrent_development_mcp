# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class MergeAuthorizationV1Transformer
      include Dry::Monads[:result]

      def initialize(
        context_resolver:,
        document_transformer:,
        stream_identity_allocator:
      )
        @context_resolver = context_resolver
        @document_transformer = document_transformer
        @stream_identity_allocator = stream_identity_allocator
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        unless source_payload.is_a?(Events::MergeAuthorizationGrantedV1) ||
            source_payload.is_a?(Events::MergeAuthorizationDeniedV1)
          return Failure(inconsistent(source_event, "unsupported authorization contract"))
        end

        transform(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source: source_payload
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      private

      def transform(
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
          source_reference: source.snapshot_binding.registration_event
        )
        return context_result if context_result.failure?

        context = context_result.value!
        validation = validate_source(
          source_event:,
          source:,
          context:,
          source_upper_position:
        )
        return validation if validation.failure?

        common = {
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:
        }
        binding = @document_transformer.snapshot_binding(
          **common,
          context:,
          binding: source.snapshot_binding
        )
        return binding if binding.failure?

        evaluation = @document_transformer.evaluation(
          **common,
          context:,
          evaluation: source.evaluation
        )
        return evaluation if evaluation.failure?

        expected_policy = @document_transformer.expected_impact_policy(
          **common,
          policy: source.expected_impact_policy
        )
        return expected_policy if expected_policy.failure?

        allocation = @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_context: "DevelopmentIntegration",
          target_stream_name: "MergeAuthorization",
          identity_role: "merge-authorization"
        )
        return allocation if allocation.failure?

        target_stream = allocation.value!.target_stream
        event_class, outcome, step_name = target_contract(source)
        markers = context.markers + [
          "merge-authorization:#{target_stream.stream_id}",
          "merge-authorization-outcome:#{outcome}",
          "merge-authorization-policy:#{source.policy_version}"
        ]
        current_policy = evaluation.value!.current_policy
        markers << "decision-partition:#{current_policy.partition.partition_id}" if current_policy
        Success([
          TransformedFactV1.new(
            target_stream:,
            event: event_class.new(
              authorization_id: target_stream.stream_id,
              merge_snapshot_id: context.merge_snapshot_id,
              evaluation: evaluation.value!,
              snapshot_binding: binding.value!
            ),
            markers:,
            step_name:,
            metadata_extension: MigrationMetadataExtensionV1.new(
              attributed_actor: actor_from(source_event),
              policy_version: source.policy_version,
              decision_digest: source.decision_digest,
              expected_impact_policy: expected_policy.value!,
              input_digest: source.input_digest
            )
          )
        ])
      end

      def validate_source(source_event:, source:, context:, source_upper_position:)
        stream = source_event.stream
        granted = source.is_a?(Events::MergeAuthorizationGrantedV1)
        valid = source_event.type == (granted ? "MergeAuthorizationGranted" : "MergeAuthorizationDenied") &&
                source_event.metadata.fetch("schema_version") == 1 &&
                source_event.global_position <= source_upper_position &&
                source_event.stream_revision.zero? &&
                stream.context == "DevelopmentIntegration" &&
                stream.stream_name == "MergeAuthorization" &&
                stream.stream_id == source.authorization_id &&
                source.merge_snapshot_id == context.source_registration.merge_snapshot_id &&
                source.evaluation.merge_snapshot_id == source.merge_snapshot_id &&
                source.evaluation.granted? == granted &&
                source_event.markers.include?("merge-snapshot:#{source.merge_snapshot_id}")
        return Success() if valid

        Failure(inconsistent(source_event, "authorization identity, outcome, or stream is inconsistent"))
      end

      def target_contract(source)
        if source.is_a?(Events::MergeAuthorizationGrantedV1)
          [ Events::MergeAuthorizationGrantedV2, "granted", "grant-merge-authorization" ]
        else
          [ Events::MergeAuthorizationDeniedV2, "denied", "deny-merge-authorization" ]
        end
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
          message: "Merge authorization transformation is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
