# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class PostRemodelAttemptTransformer
      include Dry::Monads[:result]

      def initialize(stream_identity_allocator:, entity_reference_resolver:)
        @stream_identity_allocator = stream_identity_allocator
        @entity_reference_resolver = entity_reference_resolver
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        allocation = @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_context: "DevelopmentExecution",
          target_stream_name: "Attempt",
          identity_role: "attempt"
        )
        return allocation if allocation.failure?

        transform(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source: source_payload,
          target_stream: allocation.value!.target_stream
        )
      end

      private

      def transform(migration_id:, source_config_name:, source_upper_position:, source_event:, source:, target_stream:)
        attempt_id = target_stream.stream_id
        case source
        when Events::AttemptAuthorizedV2
          success(target_stream:, source_event:, event: Events::AttemptAuthorizedV2.new(attempt_id:),
                  markers: markers(attempt_id), step_name: "authorize-attempt")
        when Events::AttemptAssignedToAgentV1
          success(
            target_stream:,
            source_event:,
            event: Events::AttemptAssignedToAgentV1.new(attempt_id:, agent_id: source.agent_id),
            markers: markers(attempt_id),
            step_name: "assign-attempt-to-agent"
          )
        when Events::AttemptAssignedToWorkItemV1
          transform_work_item_assignment(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source:,
            target_stream:
          )
        when Events::AttemptBaseSnapshotRecordedV1
          transform_snapshot(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source:,
            target_stream:
          )
        when Events::AttemptStartedV2
          success(target_stream:, source_event:, event: Events::AttemptStartedV2.new(attempt_id:),
                  markers: markers(attempt_id), step_name: "start-attempt")
        when Events::AttemptCompletedV2
          success(target_stream:, source_event:, event: Events::AttemptCompletedV2.new(attempt_id:),
                  markers: markers(attempt_id), step_name: "complete-attempt")
        when Events::AttemptAbandonedV3
          success(
            target_stream:,
            source_event:,
            event: Events::AttemptAbandonedV3.new(attempt_id:, reason: source.reason),
            markers: markers(attempt_id),
            step_name: "abandon-attempt"
          )
        end
      end

      def transform_work_item_assignment(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        target_stream:
      )
        change_set = resolve(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_context: "DevelopmentPlanning",
          source_name: "ChangeSet",
          source_id: source.change_set_id,
          target_context: "DevelopmentPlanning",
          target_name: "ChangeSet",
          identity_role: "change-set"
        )
        return change_set if change_set.failure?

        work_item = resolve(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_context: "DevelopmentExecution",
          source_name: "WorkItem",
          source_id: source.work_item_id,
          target_context: "DevelopmentExecution",
          target_name: "WorkItem",
          identity_role: "work-item"
        )
        return work_item if work_item.failure?

        attempt_id = target_stream.stream_id
        change_set_id = change_set.value!.target_stream.stream_id
        work_item_id = work_item.value!.target_stream.stream_id
        success(
          target_stream:,
          source_event:,
          event: Events::AttemptAssignedToWorkItemV1.new(attempt_id:, change_set_id:, work_item_id:),
          markers: markers(attempt_id, change_set_id:, work_item_id:),
          step_name: "assign-attempt-to-work-item"
        )
      end

      def transform_snapshot(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        target_stream:
      )
        repository = resolve(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_context: "DevelopmentPlanning",
          source_name: "Repository",
          source_id: source.repository_id,
          target_context: "DevelopmentPlanning",
          target_name: "Repository",
          identity_role: "repository"
        )
        return repository if repository.failure?

        attempt_id = target_stream.stream_id
        repository_id = repository.value!.target_stream.stream_id
        success(
          target_stream:,
          source_event:,
          event: Events::AttemptBaseSnapshotRecordedV1.new(
            attempt_id:,
            repository_id:,
            object_format: source.object_format,
            commit_oid: source.commit_oid
          ),
          markers: markers(attempt_id, repository_id:),
          step_name: "record-attempt-base-snapshot"
        )
      end

      def resolve(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_context:,
        source_name:,
        source_id:,
        target_context:,
        target_name:,
        identity_role:
      )
        @entity_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_stream: StreamReference.new(
            context: source_context,
            stream_name: source_name,
            stream_id: source_id
          ),
          target_stream_context: target_context,
          target_stream_name: target_name,
          identity_role:
        )
      end

      def success(target_stream:, source_event:, event:, markers:, step_name:)
        Success([
          TransformedFactV1.new(
            target_stream:,
            event:,
            markers:,
            step_name:,
            metadata_extension: MigrationMetadataExtensionV1.new(
              attributed_actor: Commands::Actor.new(
                kind: source_event.metadata.fetch("actor_kind"),
                id: source_event.metadata.fetch("actor_id")
              ),
              policy_version: source_event.metadata["policy_version"]
            )
          )
        ])
      end

      def markers(attempt_id, change_set_id: nil, work_item_id: nil, repository_id: nil)
        [
          "attempt:#{attempt_id}",
          ("change-set:#{change_set_id}" if change_set_id),
          ("work-item:#{work_item_id}" if work_item_id),
          ("repository:#{repository_id}" if repository_id)
        ].compact
      end
    end
  end
end
