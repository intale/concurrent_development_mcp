# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteEvaluateWorkItemReadiness < Dry::Operation
      def initialize(
        event_store:,
        decider: Domain::WorkItems::EvaluateReadiness.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        invocation_contract: Contracts::ReadinessInvocation.new,
        event_plan_contract: Contracts::ReadinessEventPlan.new
      )
        @event_store = event_store
        @decider = decider
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @invocation_contract = invocation_contract
        @event_plan_contract = event_plan_contract
      end

      def call(invocation)
        verify_invocation!(invocation)
        prepared = PreparedReadinessDecision.new(
          occurred_at: @clock.now,
          event_id: @id_generator.uuid_v7
        )

        step @event_store.multiple { execute_attempt(invocation:, prepared:) }
      end

      private

      def verify_invocation!(invocation)
        result = @invocation_contract.call(invocation:)
        raise InvalidReadinessInvocation, result.errors.to_h.inspect if result.failure?
      end

      def execute_attempt(invocation:, prepared:)
        command = invocation.command
        change_set_state = load_change_set_state(command.change_set_id)
        work_item_state = load_work_item_state(command.work_item_id)
        decision = @decider.call(
          change_set_state:,
          work_item_state:,
          command:,
          occurred_at: prepared.occurred_at,
          decision_recorded: decision_recorded?(command)
        )
        return decision if decision.failure?

        persisted_event = persist(
          decision.value!,
          invocation:,
          prepared:,
          repository_id: work_item_state.repository_id
        )

        Success(persisted_event)
      end

      def decision_recorded?(command)
        criteria = MarkedEventReadCriteria.new(
          event_type: "WorkItemMadeReady",
          marker: command.process_decision_marker,
          maximum_count: 1,
          direction: :desc
        )

        @event_store.read_marked(@stream_factory.work_item(command.work_item_id), criteria).any?
      end

      def load_change_set_state(change_set_id)
        events = @event_store.read(
          @stream_factory.change_set(change_set_id),
          EventQueries::CHANGE_SET_FOR_READINESS_EVALUATION
        ).map { load_event(_1) }

        Domain::ChangeSets::State.reduce(events)
      end

      def load_work_item_state(work_item_id)
        events = @event_store.read_grouped(
          @stream_factory.work_item(work_item_id),
          EventQueries::WORK_ITEM_FOR_READINESS_EVALUATION
        ).reverse.map { load_event(_1) }

        Domain::WorkItems::State.reduce(events)
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def persist(plan, invocation:, prepared:, repository_id:)
        command = invocation.command
        expected_stream = @stream_factory.work_item(command.work_item_id)
        verify_event_plan!(plan, expected_stream:)
        write = plan.writes.sole
        event = @event_factory.build!(
          event: write.event,
          event_id: prepared.event_id,
          metadata: event_metadata(invocation),
          markers: event_markers(command, repository_id:),
          caused_by: invocation.caused_by
        )

        @event_store.append(write.stream, [ event ]).sole
      end

      def verify_event_plan!(plan, expected_stream:)
        result = @event_plan_contract.call(plan:, expected_stream:)
        raise InvalidReadinessEventPlan, result.errors.to_h.inspect if result.failure?
      end

      def event_markers(command, repository_id:)
        command.process_decision_components + [
          command.process_decision_marker,
          "change-set:#{command.change_set_id}",
          "work-item:#{command.work_item_id}",
          "repository:#{repository_id}",
          "command:#{command.command_id}"
        ]
      end

      def event_metadata(invocation)
        command = invocation.command

        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: command.policy_version
        )
      end
    end
  end
end
