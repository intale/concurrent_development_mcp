# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class CoordinationTaskSubmittedV2Transformer
      include Dry::Monads[:result]

      def initialize(
        stream_identity_allocator:,
        submission_resolver:,
        command_input_rebinder:,
        operation_batch_context_resolver:,
        command_input_loader: LegacyCommandInputLoader.new,
        manifest_builder: OperationBatches::ManifestBuilder.new,
        request_marker: CommandLifecycle::RequestMarker.new,
        execution_lane: Tasks::ExecutionLane.new
      )
        @stream_identity_allocator = stream_identity_allocator
        @submission_resolver = submission_resolver
        @command_input_rebinder = command_input_rebinder
        @operation_batch_context_resolver = operation_batch_context_resolver
        @command_input_loader = command_input_loader
        @manifest_builder = manifest_builder
        @request_marker = request_marker
        @execution_lane = execution_lane
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        submission = @submission_resolver.call(source_event:, source_upper_position:)
        return submission if submission.failure?
        return Success([]) unless submission.value!.canonical?

        command = allocate(
          migration_id:,
          source_config_name:,
          source_event: submission.value!.command_identity_event,
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

        migrated_input = migrated_input(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source: source_payload,
          command_id: command.value!.target_stream.stream_id
        )
        return migrated_input if migrated_input.failure?

        Success(
          facts(
            source_payload,
            source_event:,
            command: command.value!,
            task: task.value!,
            migrated_input: migrated_input.value!
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

      def facts(source, source_event:, command:, task:, migrated_input:)
        command_id = command.target_stream.stream_id
        task_id = task.target_stream.stream_id
        request_id = "historical-request:#{source_event.global_position}"
        actor = actor_from(migrated_input.document)
        tool_name = migrated_input.document.tool_name
        request_marker = @request_marker.call(actor:, request_id:)
        metadata_extension = MigrationMetadataExtensionV1.new(
          attributed_actor: actor,
          canonical_input_digest: migrated_input.canonical_input_digest
        )

        [
          TransformedFactV1.new(
            target_stream: command.target_stream,
            event: Events::CommandRegisteredV1.new(
              command_id:,
              request_id:,
              tool_name:
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
              tool_name:,
              command_input: migrated_input.document,
              poll_interval_ms: source.poll_interval_ms,
              ttl_ms: source.ttl_ms
            ),
            markers: [
              "task:#{task_id}",
              "command:#{command_id}",
              request_marker,
              @execution_lane.marker(task_id),
              "tool:#{tool_name}"
            ],
            step_name: "submit-coordination-task",
            metadata_extension:
          )
        ]
      end

      def migrated_input(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        command_id:
      )
        document = @command_input_loader.call(source.command_input)
        if document.is_a?(LegacyCommandInputDocuments::CreateOperationBatchV1)
          return migrated_operation_batch_input(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            document:,
            command_id:
          )
        end

        @command_input_rebinder.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          document:,
          command_id:
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(invalid(source_event, error.message))
      end

      def migrated_operation_batch_input(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        document:,
        command_id:
      )
        source = document.input
        context = @operation_batch_context_resolver.from_identity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_batch_id: source.batch_id
        )
        return context if context.failure?

        batch = context.value!
        items = batch.items.map do |item|
          OperationBatches::ItemV1.new(
            index: item.index,
            command_input: item.submitted_input,
            canonical_input_digest: item.canonical_input_digest
          )
        end
        actor = Commands::Actor.new(
          kind: source.actor.actor_kind,
          id: source.actor.actor_id
        )
        input = CommandInputDocuments::CreateOperationBatchInputV1.new(
          actor: source.actor,
          batch_id: batch.batch_id,
          target_tool: source.target_tool,
          items:,
          manifest_digest: @manifest_builder.digest(items),
          encoded_byte_size: @manifest_builder.encoded_byte_size(
            command_id:,
            actor:,
            batch_id: batch.batch_id,
            target_tool: source.target_tool,
            items:
          ),
          page_size: source.page_size
        )
        rebound = CommandInputDocuments::CreateOperationBatchV1.new(
          schema: document.schema,
          command_id:,
          tool_name: document.tool_name,
          input:
        )
        @command_input_rebinder.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          document: rebound,
          command_id:
        )
      end

      def actor_from(document)
        Commands::Actor.new(
          kind: document.input.actor.actor_kind,
          id: document.input.actor.actor_id
        )
      end

      def invalid(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Legacy CoordinationTask command input is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
