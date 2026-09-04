# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteActivateChangeSet < Dry::Operation
      TOOL_NAME = "change_set_activate"

      def initialize(
        event_store:,
        preparer: PrepareActivateChangeSet.new,
        decider: Domain::ChangeSets::Activate.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandResultBuilder.new,
        change_set_state_loader: ChangeSets::StateLoader.new(event_store:)
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
        @change_set_state_loader = change_set_state_loader
      end

      def call(input)
        command = step @preparer.call(input)
        step call_command(command)
      end

      def call_command(command, caused_by: nil)
        steps do
          prepared = prepare_logical_values(command)

          step @event_store.multiple { execute_attempt(command:, prepared:, caused_by:) }
        end
      end

      private

      def prepare_logical_values(command)
        {
          occurred_at: @clock.now,
          input_digest: @input_digest.change_set_activate(command),
          domain_event_id: @id_generator.uuid_v7,
        }.freeze
      end

      def execute_attempt(command:, prepared:, caused_by:)
        decision = @decider.call(
          state: load_change_set_state(command.change_set_id),
          command:,
          occurred_at: prepared.fetch(:occurred_at)
        )
        return decision if decision.failure?

        persisted_domain_events = persist_domain_plan(
          decision.value!,
          command:,
          event_id: prepared.fetch(:domain_event_id),
          caused_by:
        )
        completion = @completion_builder.change_set_activate(
          command:,
          input_digest: prepared.fetch(:input_digest),
          persisted_events: persisted_domain_events,
          completed_at: prepared.fetch(:occurred_at)
        )

        Success(completion)
      end

      def load_change_set_state(change_set_id)
        @change_set_state_loader.call(change_set_id)
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def persist_domain_plan(plan, command:, event_id:, caused_by:)
        expected_stream = @stream_factory.change_set(command.change_set_id)
        write = plan.writes.sole
        unless write.stream == expected_stream && write.event.class == Events::ChangeSetActivatedV2
          raise "ActivateChangeSet plan does not match its frozen ChangeSet-stream contract"
        end

        event = @event_factory.build!(
          event: write.event,
          event_id:,
          metadata: command_metadata(command),
          markers: [
            "change-set:#{command.change_set_id}",
            "command:#{command.command_id}"
          ],
          caused_by:
        )

        @event_store.append(write.stream, [ event ])
      end

      def command_metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: nil
        )
      end
    end
  end
end
