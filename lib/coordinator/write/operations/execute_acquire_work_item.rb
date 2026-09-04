# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteAcquireWorkItem < Dry::Operation
      TOOL_NAME = "work_item_acquire"

      def initialize(
        event_store:,
        preparer: PrepareAcquireWorkItem.new,
        decider: Domain::WorkItems::Acquire.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandResultBuilder.new,
        event_plan_contract: Contracts::AcquisitionEventPlan.new,
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
        @event_plan_contract = event_plan_contract
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
        PreparedAcquisition.new(
          occurred_at: @clock.now,
          input_digest: @input_digest.work_item_acquire(command),
          domain_event_ids: (5 + command.base_snapshots.length).times.map { @id_generator.uuid_v7 },
        )
      end

      def execute_attempt(command:, prepared:, caused_by:)
        decision = @decider.call(
          change_set_state: load_change_set_state(command.change_set_id),
          work_item_state: load_work_item_state(command.work_item_id),
          attempt_state: load_attempt_state(command.attempt_id),
          command:,
          occurred_at: prepared.occurred_at
        )
        return decision if decision.failure?

        persisted_domain_events = persist_domain_plan(
          decision.value!,
          command:,
          prepared:,
          caused_by:
        )
        completion = @completion_builder.work_item_acquire(
          command:,
          input_digest: prepared.input_digest,
          persisted_events: persisted_domain_events,
          completed_at: prepared.occurred_at
        )

        Success(completion)
      end

      def load_change_set_state(change_set_id)
        @change_set_state_loader.call(change_set_id)
      end

      def load_work_item_state(work_item_id)
        events = @event_store.read_grouped(
          @stream_factory.work_item(work_item_id),
          EventQueries::WORK_ITEM_FOR_ACQUISITION
        ).map { load_event(_1) }

        Domain::WorkItems::State.reduce(events)
      end

      def load_attempt_state(attempt_id)
        events = @event_store.read(
          @stream_factory.attempt(attempt_id),
          EventQueries::ATTEMPT_FOR_ACQUISITION
        ).map { load_event(_1) }

        Domain::Attempts::State.reduce(events)
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def persist_domain_plan(plan, command:, prepared:, caused_by:)
        work_item_stream = @stream_factory.work_item(command.work_item_id)
        attempt_stream = @stream_factory.attempt(command.attempt_id)
        verify_event_plan!(plan, command:, work_item_stream:, attempt_stream:)
        metadata = command_metadata(command)

        plan.writes.zip(prepared.domain_event_ids).map do |write, event_id|
          event = @event_factory.build!(
            event: write.event,
            event_id:,
            metadata:,
            markers: event_markers(command),
            caused_by:
          )

          @event_store.append(write.stream, [ event ]).fetch(0)
        end
      end

      def verify_event_plan!(plan, command:, work_item_stream:, attempt_stream:)
        result = @event_plan_contract.call(plan:, command:, work_item_stream:, attempt_stream:)
        raise InvalidAcquisitionEventPlan, result.errors.to_h.inspect if result.failure?
      end

      def event_markers(command)
        snapshot = command.base_snapshots.sole

        [
          "change-set:#{command.change_set_id}",
          "work-item:#{command.work_item_id}",
          "attempt:#{command.attempt_id}",
          "repository:#{snapshot.repository_id}",
          "command:#{command.command_id}"
        ]
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
