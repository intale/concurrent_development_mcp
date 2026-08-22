# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteDeclareWorkItemDependency < Dry::Operation
      TOOL_NAME = "work_item_dependency_declare"

      def initialize(
        event_store:,
        preparer: PrepareDeclareWorkItemDependency.new,
        decider: Domain::ChangeSets::DeclareWorkItemDependency.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandCompletionBuilder.new
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
          prepared = prepare_logical_values(command)

          step @event_store.multiple { execute_attempt(command:, prepared:, caused_by:) }
        end
      end

      private

      def prepare_logical_values(command)
        {
          occurred_at: @clock.now,
          input_digest: @input_digest.work_item_dependency_declare(command),
          domain_event_id: @id_generator.uuid_v7,
          completion_event_id: @id_generator.uuid_v7
        }.freeze
      end

      def execute_attempt(command:, prepared:, caused_by:)
        replay = replay_result(command:, input_digest: prepared.fetch(:input_digest))
        return replay if replay

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
        completion = @completion_builder.work_item_dependency_declare(
          command:,
          input_digest: prepared.fetch(:input_digest),
          persisted_events: persisted_domain_events,
          completed_at: prepared.fetch(:occurred_at)
        )
        persist_completion(
          completion,
          command:,
          event_id: prepared.fetch(:completion_event_id),
          caused_by:
        )

        Success(completion)
      end

      def replay_result(command:, input_digest:)
        completion = load_completion(command.command_id)
        return unless completion

        if completion.tool_name == TOOL_NAME && completion.canonical_input_digest == input_digest
          Success(completion)
        else
          Failure(
            OutcomeError.new(
              code: :command_id_reused,
              message: "Command ID is already bound to another tool or input",
              details: {
                command_id: command.command_id,
                existing_tool_name: completion.tool_name,
                existing_input_digest: completion.canonical_input_digest,
                requested_tool_name: TOOL_NAME,
                requested_input_digest: input_digest
              }
            )
          )
        end
      end

      def load_completion(command_id)
        event = @event_store.read(
          @stream_factory.command(command_id),
          EventQueries::COMMAND_COMPLETION
        ).first
        return unless event

        load_event(event)
      end

      def load_change_set_state(change_set_id)
        events = @event_store.read(
          @stream_factory.change_set(change_set_id),
          EventQueries::CHANGE_SET_FOR_DEPENDENCY_DECLARATION
        ).map { load_event(_1) }

        Domain::ChangeSets::State.reduce(events)
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
        unless write.stream == expected_stream
          raise "DeclareWorkItemDependency plan does not match its frozen ChangeSet-stream contract"
        end

        event = @event_factory.build!(
          event: write.event,
          event_id:,
          metadata: command_metadata(command),
          markers: [
            "change-set:#{command.change_set_id}",
            "command:#{command.command_id}",
            "dependency:#{command.dependency_id}",
            "work-item:#{command.producer_work_item_id}",
            "work-item:#{command.consumer_work_item_id}"
          ],
          caused_by:
        )

        @event_store.append(write.stream, [ event ])
      end

      def persist_completion(completion, command:, event_id:, caused_by:)
        event = @event_factory.build!(
          event: completion,
          event_id:,
          metadata: command_metadata(command),
          markers: [ "command:#{command.command_id}" ],
          caused_by:
        )

        @event_store.append(@stream_factory.command(command.command_id), [ event ])
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
