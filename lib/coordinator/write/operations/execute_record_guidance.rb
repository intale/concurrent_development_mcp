# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteRecordGuidance < Dry::Operation
      TOOL_NAME = "guidance_record"

      def initialize(
        event_store:,
        preparer: PrepareRecordGuidance.new,
        decider: Domain::Guidance::Record.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandResultBuilder.new
      )
        @event_store = event_store
        @preparer = preparer
        @decider = decider
        @input_digest = input_digest
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @completion_builder = completion_builder
      end

      def call(input)
        command = step @preparer.call(input)
        step call_command(command)
      end

      def call_command(command, caused_by: nil)
        steps do
          preparation = prepare_logical_values(command)

          step @event_store.multiple { execute_attempt(command:, preparation:, caused_by:) }
        end
      end

      private

      def prepare_logical_values(command)
        GuidanceRecordPreparationV1.new(
          occurred_at: @clock.now,
          input_digest: @input_digest.guidance_record(command),
          domain_event_id: @id_generator.uuid_v7,
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        state = load_guidance_state(command.message_id)
        decision = @decider.call(state:, command:, occurred_at: preparation.occurred_at)
        return decision if decision.failure?

        persisted_events = persist_domain_plan(
          decision.value!,
          command:,
          event_id: preparation.domain_event_id,
          caused_by:
        )
        completion = @completion_builder.guidance_record(
          command:,
          input_digest: preparation.input_digest,
          persisted_events:,
          completed_at: preparation.occurred_at
        )

        Success(completion)
      end

      def load_guidance_state(message_id)
        events = @event_store.read_global_marked(
          EventQueries.guidance_message(message_marker(message_id))
        ).map { load_event(_1) }

        Domain::Guidance::State.reduce(events)
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def persist_domain_plan(plan, command:, event_id:, caused_by:)
        expected_stream = @stream_factory.conversation(command.conversation_id)
        unless plan.writes.length == 1 && plan.writes.first.stream == expected_stream
          raise "RecordGuidance domain plan must contain one write to its Conversation stream"
        end

        persisted = @event_factory.build!(
          event: plan.writes.first.event,
          event_id:,
          metadata: command_metadata(command),
          markers: [
            message_marker(command.message_id),
            "conversation:#{command.conversation_id}",
            "command:#{command.command_id}"
          ],
          caused_by:
        )

        @event_store.append(expected_stream, [ persisted ])
      end

      def message_marker(message_id)
        "message:#{message_id}"
      end

      def command_metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: "guidance-evidence/v1"
        )
      end
    end
  end
end
