# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class AttemptV1Transformer
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

        target_stream = allocation.value!.target_stream
        attempt_id = target_stream.stream_id
        case source_payload
        when Events::AttemptAuthorizedV1
          authorized_facts(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload,
            target_stream:,
            attempt_id:
          )
        when Events::AttemptStartedV1
          Success([
            fact(
              target_stream:,
              event: Events::AttemptStartedV2.new(attempt_id:),
              markers: markers(attempt_id:),
              step_name: "start-attempt"
            )
          ])
        when Events::AttemptCompletedV1
          Success([
            fact(
              target_stream:,
              event: Events::AttemptCompletedV2.new(attempt_id:),
              markers: markers(attempt_id:),
              step_name: "complete-attempt"
            )
          ])
        when Events::AttemptAbandonedV2
          Success([
            fact(
              target_stream:,
              event: Events::AttemptAbandonedV3.new(attempt_id:, reason: source_payload.reason),
              markers: markers(attempt_id:),
              step_name: "abandon-attempt"
            )
          ])
        end
      end

      private

      def authorized_facts(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        target_stream:,
        attempt_id:
      )
        change_set = resolve_entity(
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

        work_item = resolve_entity(
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

        snapshots = resolve_snapshots(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          snapshots: source.base_snapshots
        )
        return snapshots if snapshots.failure?

        change_set_id = change_set.value!.target_stream.stream_id
        work_item_id = work_item.value!.target_stream.stream_id
        snapshot_facts = snapshots.value!.each_with_index.map do |(snapshot, repository_id), index|
          fact(
            target_stream:,
            event: Events::AttemptBaseSnapshotRecordedV1.new(
              attempt_id:,
              repository_id:,
              object_format: snapshot.object_format,
              commit_oid: snapshot.commit_oid
            ),
            markers: markers(
              attempt_id:,
              change_set_id:,
              work_item_id:,
              repository_id:
            ),
            step_name: format("record-attempt-base-snapshot-%02d", index + 1)
          )
        end
        common = markers(attempt_id:, change_set_id:, work_item_id:)
        Success([
          fact(
            target_stream:,
            event: Events::AttemptAuthorizedV2.new(attempt_id:),
            markers: common,
            step_name: "authorize-attempt"
          ),
          fact(
            target_stream:,
            event: Events::AttemptAssignedToWorkItemV1.new(
              attempt_id:,
              change_set_id:,
              work_item_id:
            ),
            markers: common,
            step_name: "assign-attempt-to-work-item"
          ),
          fact(
            target_stream:,
            event: Events::AttemptAssignedToAgentV1.new(
              attempt_id:,
              agent_id: source.agent_id
            ),
            markers: common,
            step_name: "assign-attempt-to-agent"
          ),
          *snapshot_facts
        ])
      end

      def resolve_snapshots(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        snapshots:
      )
        resolved = []
        snapshots.each do |snapshot|
          repository = resolve_entity(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source_context: "DevelopmentPlanning",
            source_name: "Repository",
            source_id: snapshot.repository_id,
            target_context: "DevelopmentPlanning",
            target_name: "Repository",
            identity_role: "repository"
          )
          return repository if repository.failure?

          resolved << [ snapshot, repository.value!.target_stream.stream_id ]
        end
        Success(resolved.freeze)
      end

      def resolve_entity(
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

      def fact(target_stream:, event:, markers:, step_name:)
        TransformedFactV1.new(target_stream:, event:, markers:, step_name:)
      end

      def markers(attempt_id:, change_set_id: nil, work_item_id: nil, repository_id: nil)
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
