# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteCompleteCompensatedReleaseSet < Dry::Operation
      TOOL_NAME = "release_compensation_complete"

      def initialize(
        event_store:,
        preparer: PrepareCompleteCompensatedReleaseSet.new,
        history_loader: ReleaseSets::HistoryLoader.new(event_store:),
        decider: Domain::ReleaseSets::CompleteCompensated.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandCompletionBuilder.new,
        event_plan_contract: Contracts::ReleaseSetCompensatedCompletionEventPlan.new
      )
        @event_store = event_store
        @preparer = preparer
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
        ReleaseSetLifecyclePreparationV1.new(
          occurred_at: @clock.now,
          input_digest: @input_digest.release_compensation_complete(command),
          domain_event_id: @id_generator.uuid_v7,
          completion_event_id: @id_generator.uuid_v7
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        replay = replay_result(command:, input_digest: preparation.input_digest)
        return replay if replay

        state = @history_loader.call(command.release_set_id)
        decision = @decider.call(state:, command:, completed_at: preparation.occurred_at)
        return decision if decision.failure?

        plan = decision.value!
        verify_event_plan!(plan, state:, command:, completed_at: preparation.occurred_at)
        completion_fact = plan.events.sole
        persisted = persist_domain(completion_fact, state:, command:, preparation:, caused_by:)
        completion = @completion_builder.release_compensation_complete(
          command:, completion: completion_fact, input_digest: preparation.input_digest,
          persisted_events: [ persisted ], completed_at: preparation.occurred_at
        )
        persist_completion(completion, state:, command:, preparation:, caused_by:)
        Success(completion)
      end

      def verify_event_plan!(plan, state:, command:, completed_at:)
        result = @event_plan_contract.call(plan:, state:, command:, completed_at:)
        raise InvalidReleaseSetCompensatedCompletionEventPlan, result.errors.to_h.inspect if result.failure?
      end

      def persist_domain(completion, state:, command:, preparation:, caused_by:)
        physical = @event_factory.build!(
          event: completion,
          event_id: preparation.domain_event_id,
          metadata: command_metadata(command),
          markers: [ "release-set:#{command.release_set_id}", "release-completion:compensated", "command:#{command.command_id}" ],
          caused_by:,
          correlation_id: state.preparation.correlation_id
        )
        @event_store.append(@stream_factory.release_set(command.release_set_id), [ physical ]).sole
      end

      def persist_completion(completion, state:, command:, preparation:, caused_by:)
        physical = @event_factory.build!(
          event: completion,
          event_id: preparation.completion_event_id,
          metadata: command_metadata(command), markers: [ "command:#{command.command_id}" ],
          caused_by:, correlation_id: state.preparation.correlation_id
        )
        @event_store.append(@stream_factory.command(command.command_id), [ physical ])
      end

      def replay_result(command:, input_digest:)
        completion = load_completion(command.command_id)
        return unless completion
        return Success(completion) if completion.tool_name == TOOL_NAME && completion.canonical_input_digest == input_digest

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

      def load_completion(command_id)
        event = @event_store.read(@stream_factory.command(command_id), EventQueries::COMMAND_COMPLETION).first
        event && @schema_registry.load(type: event.type, schema_version: event.metadata.fetch("schema_version"), data: event.data)
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
