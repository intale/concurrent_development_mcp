# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteRequestReleaseSetCompensation < Dry::Operation
      TOOL_NAME = "release_compensation_request_policy"

      def initialize(
        event_store:,
        history_loader: ReleaseSets::HistoryLoader.new(event_store:),
        decider: Domain::ReleaseSets::RequestCompensation.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandResultBuilder.new,
        event_plan_contract: Contracts::ReleaseSetCompensationRequestEventPlan.new
      )
        @event_store = event_store
        @history_loader = history_loader
        @decider = decider
        @input_digest = input_digest
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @completion_builder = completion_builder
        @event_plan_contract = event_plan_contract
      end

      def call_command(command, caused_by:)
        steps do
          preparation = prepare_logical_values(command)
          step @event_store.multiple { execute_attempt(command:, preparation:, caused_by:) }
        end
      end

      private

      def prepare_logical_values(command)
        ReleaseSetLifecyclePreparationV1.new(
          occurred_at: @clock.now,
          input_digest: @input_digest.release_compensation_request(command),
          domain_event_id: @id_generator.uuid_v7,
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        state = @history_loader.call(command.release_set_id)
        decision = @decider.call(state:, command:, requested_at: preparation.occurred_at)
        return decision if decision.failure?

        plan = decision.value!
        verify_event_plan!(plan, state:, command:, requested_at: preparation.occurred_at)
        request = plan.events.sole
        persisted = persist_domain(request, state:, command:, preparation:, caused_by:)
        completion = @completion_builder.release_compensation_request(
          command:, request:, input_digest: preparation.input_digest,
          persisted_events: [ persisted ], completed_at: preparation.occurred_at
        )
        Success(completion)
      end

      def verify_event_plan!(plan, state:, command:, requested_at:)
        result = @event_plan_contract.call(plan:, state:, command:, requested_at:)
        raise InvalidReleaseSetCompensationRequestEventPlan, result.errors.to_h.inspect if result.failure?
      end

      def persist_domain(request, state:, command:, preparation:, caused_by:)
        physical = @event_factory.build!(
          event: request,
          event_id: preparation.domain_event_id,
          metadata: command_metadata(command),
          markers: [
            "release-set:#{command.release_set_id}",
            "release-compensation-trigger:#{command.trigger_event.event_id}",
            "command:#{command.command_id}"
          ],
          caused_by:,
          correlation_id: state.preparation.correlation_id
        )
        @event_store.append(@stream_factory.release_set(command.release_set_id), [ physical ]).sole
      end

      def command_metadata(command)
        EventMetadata.new(
          command_id: command.command_id, actor_kind: command.actor.kind, actor_id: command.actor.id,
          recorded_by: "coordinator", policy_version: command.rule_version
        )
      end
    end
  end
end
