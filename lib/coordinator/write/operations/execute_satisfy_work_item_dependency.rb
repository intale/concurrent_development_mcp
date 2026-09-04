# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteSatisfyWorkItemDependency < Dry::Operation
      TOOL_NAME = "dependency_satisfaction_policy"

      def initialize(
        event_store:,
        source_loader: DependencySatisfactions::SourceLoader.new(event_store:),
        decider: Domain::ChangeSets::SatisfyWorkItemDependency.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandResultBuilder.new,
        event_plan_contract: Contracts::DependencySatisfactionEventPlan.new,
        change_set_state_loader: ChangeSets::StateLoader.new(event_store:)
      )
        @event_store = event_store
        @source_loader = source_loader
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

      def call(command, caused_by:)
        step call_command(command, caused_by:)
      end

      def call_command(command, caused_by:)
        steps do
          preparation = PreparedDependencySatisfactionV1.new(
            occurred_at: @clock.now,
            input_digest: @input_digest.dependency_satisfaction_policy(command),
            satisfaction_event_id: @id_generator.uuid_v7,
            readiness_event_id: @id_generator.uuid_v7,
          )

          step @event_store.multiple { execute_attempt(command:, preparation:, caused_by:) }
        end
      end

      private

      def execute_attempt(command:, preparation:, caused_by:)
        change_set_state = load_change_set(command.change_set_id)
        dependency = change_set_state.dependencies.find { _1.dependency_id == command.dependency_id }
        return dependency_not_found(command) unless dependency

        source_result = @source_loader.call(command:, dependency:)
        return source_result if source_result.failure?

        source = source_result.value!
        consumer_state = load_work_item(dependency.consumer_work_item_id)
        decision = @decider.call(
          change_set_state:,
          consumer_state:,
          command:,
          evidence: source,
          satisfied_at: preparation.occurred_at
        )
        return decision if decision.failure?

        plan = decision.value!
        verify_event_plan!(
          plan:,
          command:,
          dependency:,
          source:,
          satisfied_at: preparation.occurred_at
        )
        persisted = persist_domain(plan, command:, caused_by:, preparation:)
        satisfaction = plan.events.fetch(0)
        completion = @completion_builder.dependency_satisfaction_policy(
          command:,
          satisfaction:,
          input_digest: preparation.input_digest,
          persisted_events: persisted,
          completed_at: preparation.occurred_at
        )
        Success(completion)
      end

      def load_change_set(change_set_id)
        @change_set_state_loader.call(change_set_id)
      end

      def load_work_item(work_item_id)
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

      def verify_event_plan!(plan:, command:, dependency:, source:, satisfied_at:)
        result = @event_plan_contract.call(plan:, command:, dependency:, source:, satisfied_at:)
        return if result.success?

        raise InvalidDependencySatisfactionEventPlan, result.errors.to_h.inspect
      end

      def persist_domain(plan, command:, caused_by:, preparation:)
        event_ids = [ preparation.satisfaction_event_id, preparation.readiness_event_id ]
        plan.writes.each_with_index.map do |write, index|
          event = @event_factory.build!(
            event: write.event,
            event_id: event_ids.fetch(index),
            metadata: command_metadata(command),
            markers: event_markers(write.event, command:),
            caused_by:
          )
          @event_store.append(write.stream, [ event ]).sole
        end.freeze
      end

      def event_markers(event, command:)
        common = command.process_decision_components + [
          command.process_decision_marker,
          "change-set:#{command.change_set_id}",
          "dependency:#{command.dependency_id}",
          "source-event:#{command.source_event.event_id}",
          "command:#{command.command_id}"
        ]
        return common unless event.is_a?(Events::WorkItemDependencySatisfiedV2)

        common + [
          "producer-work-item:#{event.producer_work_item_id}",
          "consumer-work-item:#{event.consumer_work_item_id}",
          "dependency-kind:#{event.dependency_kind}"
        ]
      end

      def dependency_not_found(command)
        Failure(
          OutcomeError.new(
            code: :dependency_not_found,
            message: "Dependency is not declared",
            details: {
              change_set_id: command.change_set_id,
              dependency_id: command.dependency_id
            }
          )
        )
      end

      def command_metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: command.rule_version
        )
      end
    end
  end
end
