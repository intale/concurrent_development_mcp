# frozen_string_literal: true

module Coordinator
  module Operations
    class ExecuteCreateChangeSet < Dry::Operation
      TOOL_NAME = "change_set_create"

      def initialize(
        event_store:,
        preparer: PrepareCreateChangeSet.new,
        decider: Domain::ChangeSets::Create.new,
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
        prepared = prepare_logical_values(command)

        step @event_store.multiple { execute_attempt(command:, prepared:) }
      end

      private

      def prepare_logical_values(command)
        {
          occurred_at: @clock.now,
          input_digest: @input_digest.create_change_set(command),
          domain_event_ids: 2.times.map { @id_generator.uuid_v7 }.freeze,
          completion_event_id: @id_generator.uuid_v7
        }.freeze
      end

      def execute_attempt(command:, prepared:)
        replay = replay_result(command:, input_digest: prepared.fetch(:input_digest))
        return replay if replay

        state = load_change_set_state(command.change_set_id)
        decision = @decider.call(state:, command:, occurred_at: prepared.fetch(:occurred_at))
        return decision if decision.failure?

        persisted_domain_events = persist_domain_plan(
          decision.value!,
          command:,
          event_ids: prepared.fetch(:domain_event_ids)
        )
        completion = @completion_builder.create_change_set(
          command:,
          input_digest: prepared.fetch(:input_digest),
          persisted_events: persisted_domain_events,
          completed_at: prepared.fetch(:occurred_at)
        )
        persist_completion(
          completion,
          command:,
          event_id: prepared.fetch(:completion_event_id)
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
        stream = @stream_factory.command(command_id)
        completions = @event_store.read_all(stream).select { _1.type == "CommandCompleted" }
        raise "Command stream contains multiple completions: #{command_id}" if completions.length > 1

        event = completions.first
        return unless event

        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def load_change_set_state(change_set_id)
        events = @event_store.read_all(@stream_factory.change_set(change_set_id)).map do |event|
          @schema_registry.load(
            type: event.type,
            schema_version: event.metadata.fetch("schema_version"),
            data: event.data
          )
        end

        Domain::ChangeSets::State.reduce(events)
      end

      def persist_domain_plan(plan, command:, event_ids:)
        unless plan.writes.length == event_ids.length
          raise "Prepared event ID count does not match the decided write plan"
        end

        streams = plan.writes.map(&:stream).uniq
        raise "CreateChangeSet domain plan must target one ChangeSet stream" unless streams.one?

        metadata = command_metadata(command)
        events = plan.writes.zip(event_ids).map do |write, event_id|
          @event_factory.build!(
            event: write.event,
            event_id:,
            metadata:,
            markers: [
              "change-set:#{command.change_set_id}",
              "command:#{command.command_id}"
            ]
          )
        end

        @event_store.append(streams.first, events)
      end

      def persist_completion(completion, command:, event_id:)
        event = @event_factory.build!(
          event: completion,
          event_id:,
          metadata: command_metadata(command),
          markers: [ "command:#{command.command_id}" ]
        )

        @event_store.append(@stream_factory.command(command.command_id), [ event ])
      end

      def command_metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          correlation_id: command.command_id,
          policy_version: nil
        )
      end
    end
  end
end
