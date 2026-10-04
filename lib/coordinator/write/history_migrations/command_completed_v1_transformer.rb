# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class CommandCompletedV1Transformer
      include Dry::Monads[:result]

      def initialize(
        stream_identity_allocator:,
        submission_resolver:,
        request_id_mapper: LegacyRequestIdMapper.new,
        request_marker: CommandLifecycle::RequestMarker.new
      )
        @stream_identity_allocator = stream_identity_allocator
        @submission_resolver = submission_resolver
        @request_id_mapper = request_id_mapper
        @request_marker = request_marker
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        submission = @submission_resolver.for_completion(
          source_event:,
          source_upper_position:,
          command_id: source_payload.command_id,
        )
        return submission if submission.failure?
        resolution = submission.value!

        allocation = @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event: resolution&.command_identity_event || source_event,
          target_stream_context: "CoordinatorControl",
          target_stream_name: "Command",
          identity_role: "command"
        )
        return allocation if allocation.failure?

        Success(
          facts(
            source_payload,
            source_event:,
            target_stream: allocation.value!.target_stream,
            task_submitted: !resolution.nil?,
            batch_registered: operation_batch_registration?(allocation.value!)
          )
        )
      end

      private

      def facts(source, source_event:, target_stream:, task_submitted:, batch_registered:)
        command_id = target_stream.stream_id
        terminal = TransformedFactV1.new(
          target_stream:,
          event: Events::CommandSucceededV1.new(command_id:),
          markers: [ "command:#{command_id}", "tool:#{source.tool_name}" ],
          step_name: "succeed-command"
        )
        return [ terminal ] if task_submitted || batch_registered

        [ registration(source, source_event:, target_stream:), terminal ]
      end

      def operation_batch_registration?(allocation)
        markers = allocation.allocation_event.markers
        markers.one? { _1.start_with?("operation-batch:") } &&
          markers.one? { _1.start_with?("batch-item:") }
      end

      def registration(source, source_event:, target_stream:)
        command_id = target_stream.stream_id
        request_id = @request_id_mapper.call(
          command_id: source.command_id,
          source_position: source_event.global_position
        )
        actor = Commands::Actor.new(
          kind: source_event.metadata.fetch("actor_kind"),
          id: source_event.metadata.fetch("actor_id")
        )
        TransformedFactV1.new(
          target_stream:,
          event: Events::CommandRegisteredV1.new(
            command_id:,
            request_id:,
            tool_name: source.tool_name
          ),
          markers: [ "command:#{command_id}", @request_marker.call(actor:, request_id:) ],
          step_name: "register-standalone-command",
          metadata_extension: MigrationMetadataExtensionV1.new(
            attributed_actor: actor,
            canonical_input_digest: source.canonical_input_digest
          )
        )
      end
    end
  end
end
