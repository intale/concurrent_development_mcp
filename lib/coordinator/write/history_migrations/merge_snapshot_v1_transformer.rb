# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class MergeSnapshotV1Transformer
      include Dry::Monads[:result]

      def initialize(
        context_resolver:,
        stream_identity_allocator:,
        commit_identity_builder: MergeSnapshots::CommitIdentityBuilder.new
      )
        @context_resolver = context_resolver
        @stream_identity_allocator = stream_identity_allocator
        @commit_identity_builder = commit_identity_builder
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        case source_payload
        when Events::MergeSnapshotRegisteredV1
          transform_registration(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload
          )
        when Events::MergeSnapshotCommitRegisteredV1
          transform_commit_registration(
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

      def transform_registration(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:
      )
        resolved = @context_resolver.from_registration(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_registration: source
        )
        return resolved if resolved.failure?

        context = resolved.value!
        Success([
          fact(
            target_stream: context.snapshot_stream,
            event: Events::MergeSnapshotRegisteredV2.new(
              merge_snapshot_id: context.merge_snapshot_id,
              repository_id: context.repository_id,
              target_branch: source.target_branch,
              object_format: source.object_format,
              target_base_commit_oid: source.target_base_commit_oid,
              merge_commit_oid: source.merge_commit_oid,
              ordered_candidates: context.ordered_candidate_ids,
              producer: source.producer.name,
              run_id: source.run_id,
              produced_at: source.produced_at
            ),
            markers: context.markers,
            step_name: "register-merge-snapshot",
            metadata_extension: actor_metadata(
              source_event,
              policy_version: source.policy_version,
              snapshot_digest: source.snapshot_digest
            )
          )
        ])
      end

      def transform_commit_registration(
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
          source_reference: source.snapshot_event
        )
        return context_result if context_result.failure?

        context = context_result.value!
        validation = validate_commit(
          source_event,
          source,
          context,
          source_upper_position:
        )
        return validation if validation.failure?

        allocation = @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_context: "DevelopmentIntegration",
          target_stream_name: "MergeSnapshotCommit",
          identity_role: "merge-snapshot-commit"
        )
        return allocation if allocation.failure?

        target_stream = allocation.value!.target_stream
        identity_marker = @commit_identity_builder.call(
          repository_id: context.repository_id,
          object_format: source.object_format,
          merge_commit_oid: source.merge_commit_oid
        ).marker
        Success([
          fact(
            target_stream:,
            event: Events::MergeSnapshotCommitRegisteredV2.new(
              registry_id: target_stream.stream_id,
              merge_snapshot_id: context.merge_snapshot_id,
              repository_id: context.repository_id,
              object_format: source.object_format,
              merge_commit_oid: source.merge_commit_oid
            ),
            markers: context.markers + [
              "merge-snapshot-commit:#{target_stream.stream_id}",
              identity_marker
            ],
            step_name: "register-merge-snapshot-commit",
            metadata_extension: actor_metadata(
              source_event,
              marker_codec_version: "compound-marker-v2"
            )
          )
        ])
      end

      def validate_commit(source_event, source, context, source_upper_position:)
        registration = context.source_registration
        stream = source_event.stream
        valid = source_event.type == "MergeSnapshotCommitRegistered" &&
                source_event.metadata.fetch("schema_version") == 1 &&
                source_event.global_position <= source_upper_position &&
                source_event.stream_revision.zero? &&
                stream.context == "DevelopmentIntegration" &&
                stream.stream_name == "MergeSnapshotCommit" &&
                stream.stream_id == source.registry_id &&
                [
                  source.merge_snapshot_id,
                  source.repository_id,
                  source.object_format,
                  source.merge_commit_oid
                ] == [
                  registration.merge_snapshot_id,
                  registration.repository_id,
                  registration.object_format,
                  registration.merge_commit_oid
                ] &&
                source_event.markers.include?("merge-snapshot:#{source.merge_snapshot_id}") &&
                source_event.markers.include?("repository:#{source.repository_id}")
        return Success() if valid

        Failure(inconsistent(source_event, "merge snapshot commit registration is inconsistent"))
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
          message: "Merge snapshot transformation is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
