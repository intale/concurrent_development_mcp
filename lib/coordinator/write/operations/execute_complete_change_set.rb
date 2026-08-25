# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteCompleteChangeSet < Dry::Operation
      TOOL_NAME = "change_set_completion_policy"

      def initialize(
        event_store:,
        source_loader: ChangeSetCompletions::SourceLoader.new(event_store:),
        work_item_loader: ChangeSetCompletions::WorkItemLoader.new(event_store:),
        release_history_loader: ReleaseSets::HistoryLoader.new(event_store:),
        decider: Domain::ChangeSets::Complete.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandCompletionBuilder.new,
        event_plan_contract: Contracts::ChangeSetCompletionEventPlan.new
      )
        @event_store = event_store
        @source_loader = source_loader
        @work_item_loader = work_item_loader
        @release_history_loader = release_history_loader
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

      def call(command)
        step call_command(command)
      end

      def call_command(command)
        steps do
          preparation = PreparedChangeSetCompletionV1.new(
            occurred_at: @clock.now,
            input_digest: @input_digest.change_set_completion_policy(command),
            completion_event_id: @id_generator.uuid_v7,
            command_completion_event_id: @id_generator.uuid_v7
          )

          step @event_store.multiple { execute_attempt(command:, preparation:) }
        end
      end

      private

      def execute_attempt(command:, preparation:)
        replay = replay_result(command:, input_digest: preparation.input_digest)
        return replay if replay

        source_result = @source_loader.call(command)
        return source_result if source_result.failure?

        source = source_result.value!
        state = load_change_set(command.change_set_id)
        work_items_result = @work_item_loader.call(state)
        return work_items_result if work_items_result.failure?

        work_items = work_items_result.value!
        release_state = command.release_set_id && @release_history_loader.call(command.release_set_id)
        decision = @decider.call(
          state:,
          work_items:,
          release_state:,
          command:,
          completed_at: preparation.occurred_at
        )
        return decision if decision.failure?

        plan = decision.value!
        verify_event_plan!(
          plan:,
          command:,
          work_items:,
          release_state:,
          completed_at: preparation.occurred_at
        )
        persisted = persist_completion_fact(
          plan.events.sole,
          command:,
          source:,
          event_id: preparation.completion_event_id
        )
        completion = @completion_builder.change_set_completion_policy(
          command:,
          completion: plan.events.sole,
          input_digest: preparation.input_digest,
          persisted_events: [ persisted ],
          completed_at: preparation.occurred_at
        )
        persist_command_completion(
          completion,
          command:,
          source:,
          event_id: preparation.command_completion_event_id
        )
        Success(completion)
      end

      def load_change_set(change_set_id)
        events = @event_store.read(
          @stream_factory.change_set(change_set_id),
          EventQueries::CHANGE_SET_FOR_COMPLETION
        ).map { load_event(_1) }
        Domain::ChangeSets::State.reduce(events)
      end

      def verify_event_plan!(plan:, command:, work_items:, release_state:, completed_at:)
        result = @event_plan_contract.call(
          plan:,
          command:,
          work_items:,
          release_state:,
          completed_at:
        )
        return if result.success?

        raise InvalidChangeSetCompletionEventPlan, result.errors.to_h.inspect
      end

      def persist_completion_fact(completion, command:, source:, event_id:)
        physical = @event_factory.build!(
          event: completion,
          event_id:,
          metadata: command_metadata(command),
          markers: completion_markers(completion, command:),
          caused_by: source.event
        )
        @event_store.append(@stream_factory.change_set(command.change_set_id), [ physical ]).sole
      end

      def persist_command_completion(completion, command:, source:, event_id:)
        physical = @event_factory.build!(
          event: completion,
          event_id:,
          metadata: command_metadata(command),
          markers: [ "command:#{command.command_id}" ],
          caused_by: source.event
        )
        @event_store.append(@stream_factory.command(command.command_id), [ physical ])
      end

      def completion_markers(_completion, command:)
        markers = command.process_decision_components + [
          command.process_decision_marker,
          "change-set:#{command.change_set_id}",
          "change-set-status:completed",
          "command:#{command.command_id}"
        ]
        markers << "release-set:#{command.release_set_id}" if command.release_set_id
        markers.uniq.freeze
      end

      def replay_result(command:, input_digest:)
        completion = load_completion(command.command_id)
        return unless completion
        return Success(completion) if completion.tool_name == TOOL_NAME && completion.canonical_input_digest == input_digest

        Failure(
          OutcomeError.new(
            code: :command_id_reused,
            message: "Command ID is already bound to another tool or input",
            details: {}
          )
        )
      end

      def load_completion(command_id)
        event = @event_store.read(@stream_factory.command(command_id), EventQueries::COMMAND_COMPLETION).first
        event && load_event(event)
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
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
