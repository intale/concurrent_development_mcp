# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class MergeObservationV1Transformer
      include Dry::Monads[:result]

      def initialize(
        context_resolver:,
        document_transformer:,
        reference_resolver:
      )
        @context_resolver = context_resolver
        @document_transformer = document_transformer
        @reference_resolver = reference_resolver
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        unless source_payload.is_a?(Events::MergeObservedV1)
          return Failure(inconsistent(source_event, "unsupported observation contract"))
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
        authorization = @reference_resolver.load_reference(
          source_event:,
          source_upper_position:,
          source_reference: source.authorization_event
        )
        return authorization if authorization.failure?

        source_authorization = authorization.value!.last
        validation = validate_source(
          source_event:,
          source:,
          context:,
          source_authorization:,
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

        target_authorization = @reference_resolver.call(
          **common,
          source_reference: source.authorization_event
        )
        return target_authorization if target_authorization.failure?

        authorization_reference = target_authorization.value!
        markers = context.markers + [
          "merge-authorization:#{authorization_reference.stream_id}",
          "repository:#{context.repository_id}",
          "target-branch:#{source.target_branch}",
          "merge-snapshot-status:observed"
        ]
        actor = actor_metadata(source_event)
        Success([
          fact(
            target_stream: context.snapshot_stream,
            event: Events::MergeObservedV2.new(
              merge_snapshot_id: context.merge_snapshot_id,
              repository_id: context.repository_id,
              target_branch: source.target_branch,
              object_format: source.object_format,
              target_before_commit_oid: source.target_before_commit_oid,
              target_after_commit_oid: source.target_after_commit_oid,
              observer: source.observer.name,
              run_id: source.run_id,
              snapshot_binding: binding.value!,
              observed_at: source.observed_at
            ),
            markers:,
            step_name: "record-merge-observation",
            metadata_extension: actor_metadata(
              source_event,
              policy_version: source.policy_version,
              authorization_decision_digest: source.authorization_decision_digest,
              observation_digest: source.observation_digest
            )
          ),
          fact(
            target_stream: context.snapshot_stream,
            event: Events::MergeObservationAuthorizationLinkedV1.new(
              merge_snapshot_id: context.merge_snapshot_id,
              authorization_id: authorization_reference.stream_id,
              authorization_event: authorization_reference
            ),
            markers:,
            step_name: "link-merge-observation-authorization",
            metadata_extension: actor
          )
        ])
      end

      def validate_source(
        source_event:,
        source:,
        context:,
        source_authorization:,
        source_upper_position:
      )
        registration = context.source_registration
        stream = source_event.stream
        valid = source_event.type == "MergeObserved" &&
                source_event.metadata.fetch("schema_version") == 1 &&
                source_event.global_position <= source_upper_position &&
                stream.context == "DevelopmentIntegration" &&
                stream.stream_name == "MergeSnapshot" &&
                stream.stream_id == source.merge_snapshot_id &&
                source.merge_snapshot_id == registration.merge_snapshot_id &&
                source_authorization.is_a?(Events::MergeAuthorizationGrantedV1) &&
                source_authorization.authorization_id == source.authorization_event.stream_id &&
                source_authorization.merge_snapshot_id == source.merge_snapshot_id &&
                source_authorization.snapshot_binding == source.snapshot_binding &&
                source_authorization.decision_digest == source.authorization_decision_digest &&
                source.repository_id == registration.repository_id &&
                source.target_branch == registration.target_branch &&
                source.object_format == registration.object_format &&
                source.target_before_commit_oid == registration.target_base_commit_oid &&
                source.target_after_commit_oid == registration.merge_commit_oid &&
                source_event.markers.include?("merge-snapshot:#{source.merge_snapshot_id}")
        return Success() if valid

        Failure(inconsistent(source_event, "observation, authorization, or Git transition is inconsistent"))
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
          message: "Merge observation transformation is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
