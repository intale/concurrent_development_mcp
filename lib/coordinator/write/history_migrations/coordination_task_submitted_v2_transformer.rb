# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class CoordinationTaskSubmittedV2Transformer
      include Dry::Monads[:result]

      def initialize(
        stream_identity_allocator:,
        command_event_locator:,
        command_input_rebinder: CommandInputRebinder.new,
        request_id_mapper: LegacyRequestIdMapper.new,
        request_marker: CommandLifecycle::RequestMarker.new,
        execution_lane: Tasks::ExecutionLane.new
      )
        @stream_identity_allocator = stream_identity_allocator
        @command_event_locator = command_event_locator
        @command_input_rebinder = command_input_rebinder
        @request_id_mapper = request_id_mapper
        @request_marker = request_marker
        @execution_lane = execution_lane
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        completion = @command_event_locator.completion(
          command_id: source_payload.command_id,
          through_position: source_upper_position,
          source_event:
        )
        return completion if completion.failure?

        command = allocate(
          migration_id:,
          source_config_name:,
          source_event: completion.value! || source_event,
          target_stream_name: "Command",
          identity_role: "command"
        )
        return command if command.failure?

        task = allocate(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_name: "CoordinationTask",
          identity_role: "coordination-task"
        )
        return task if task.failure?

        Success(
          facts(
            source_payload,
            source_event:,
            command: command.value!,
            task: task.value!
          )
        )
      end

      private

      def allocate(migration_id:, source_config_name:, source_event:, target_stream_name:, identity_role:)
        @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_context: "CoordinatorControl",
          target_stream_name:,
          identity_role:
        )
      end

      def facts(source, source_event:, command:, task:)
        command_id = command.target_stream.stream_id
        task_id = task.target_stream.stream_id
        migrated_input = @command_input_rebinder.call(document: source.command_input, command_id:)
        request_id = @request_id_mapper.call(
          command_id: source.command_id,
          source_position: source_event.global_position
        )
        actor = actor_from(source.command_input)
        request_marker = @request_marker.call(actor:, request_id:)
        metadata_extension = MigrationMetadataExtensionV1.new(
          canonical_input_digest: migrated_input.canonical_input_digest
        )

        [
          TransformedFactV1.new(
            target_stream: command.target_stream,
            event: Events::CommandRegisteredV1.new(
              command_id:,
              request_id:,
              tool_name: source.tool_name
            ),
            markers: [ "command:#{command_id}", "task:#{task_id}", request_marker ],
            step_name: "register-command",
            metadata_extension:
          ),
          TransformedFactV1.new(
            target_stream: task.target_stream,
            event: Events::CoordinationTaskSubmittedV3.new(
              task_id:,
              command_id:,
              tool_name: source.tool_name,
              command_input: migrated_input.document,
              poll_interval_ms: source.poll_interval_ms,
              ttl_ms: source.ttl_ms
            ),
            markers: [
              "task:#{task_id}",
              "command:#{command_id}",
              request_marker,
              @execution_lane.marker(task_id),
              "tool:#{source.tool_name}"
            ],
            step_name: "submit-coordination-task",
            metadata_extension:
          )
        ]
      end

      def actor_from(document)
        Commands::Actor.new(
          kind: document.input.actor.actor_kind,
          id: document.input.actor.actor_id
        )
      end
    end
  end
end
