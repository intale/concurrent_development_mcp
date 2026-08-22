# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteCreateWorkItem < Dry::Operation
      TOOL_NAME = "work_item_create"

      def initialize(
        event_store:,
        preparer: PrepareCreateWorkItem.new,
        decider: Domain::WorkItems::Create.new,
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
          input_digest: @input_digest.work_item_create(command),
          domain_event_ids: 2.times.map { @id_generator.uuid_v7 }.freeze,
          completion_event_id: @id_generator.uuid_v7
        }.freeze
      end

      def execute_attempt(command:, prepared:, caused_by:)
        replay = replay_result(command:, input_digest: prepared.fetch(:input_digest))
        return replay if replay

        decision = @decider.call(
          change_set_state: load_change_set_state(command.change_set_id),
          work_item_state: load_work_item_state(command.work_item_id),
          command:,
          occurred_at: prepared.fetch(:occurred_at)
        )
        return decision if decision.failure?

        persisted_domain_events = persist_domain_plan(
          decision.value!,
          command:,
          event_ids: prepared.fetch(:domain_event_ids),
          caused_by:
        )
        completion = @completion_builder.work_item_create(
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
          EventQueries::CHANGE_SET_FOR_WORK_ITEM_CREATION
        ).map { load_event(_1) }

        Domain::ChangeSets::State.reduce(events)
      end

      def load_work_item_state(work_item_id)
        events = @event_store.read_grouped(
          @stream_factory.work_item(work_item_id),
          EventQueries::WORK_ITEM_EXISTENCE
        ).map { load_event(_1) }

        Domain::WorkItems::State.reduce(events)
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def persist_domain_plan(plan, command:, event_ids:, caused_by:)
        validate_domain_plan!(plan, command:, event_ids:)
        metadata = command_metadata(command)

        plan.writes.zip(event_ids).map do |write, event_id|
          event = @event_factory.build!(
            event: write.event,
            event_id:,
            metadata:,
            markers: markers_for(write.event, command),
            caused_by:
          )

          @event_store.append(write.stream, [ event ]).fetch(0)
        end
      end

      def validate_domain_plan!(plan, command:, event_ids:)
        unless plan.writes.length == event_ids.length
          raise "Prepared event ID count does not match the decided write plan"
        end

        expected_streams = [
          @stream_factory.work_item(command.work_item_id),
          @stream_factory.change_set(command.change_set_id)
        ]
        expected_event_classes = [
          Events::WorkItemCreatedV1,
          Events::WorkItemAddedToChangeSetV1
        ]

        unless plan.writes.map(&:stream) == expected_streams && plan.events.map(&:class) == expected_event_classes
          raise "CreateWorkItem domain plan does not match its frozen cross-stream contract"
        end
      end

      def markers_for(event, command)
        markers = [
          "change-set:#{command.change_set_id}",
          "work-item:#{command.work_item_id}",
          "command:#{command.command_id}"
        ]
        markers << "repository:#{command.repository_id}" if event.is_a?(Events::WorkItemCreatedV1)
        markers
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
