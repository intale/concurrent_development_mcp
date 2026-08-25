# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteCompleteWorkItem < Dry::Operation
      TOOL_NAME = "work_item_complete"

      def initialize(
        event_store:,
        preparer: PrepareCompleteWorkItem.new,
        decider: Domain::WorkItems::Complete.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandCompletionBuilder.new,
        event_plan_contract: Contracts::WorkItemCompletionEventPlan.new
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
        PreparedWorkItemCompletionV1.new(
          completed_at: @clock.now,
          input_digest: @input_digest.work_item_complete(command),
          domain_event_ids: 3.times.map { @id_generator.uuid_v7 },
          completion_event_id: @id_generator.uuid_v7
        )
      end

      def execute_attempt(command:, prepared:, caused_by:)
        replay = replay_result(command:, input_digest: prepared.input_digest)
        return replay if replay

        candidate_event = load_candidate_event(command.candidate_id)
        candidate = candidate_event && load_event(candidate_event)
        candidate_reference = candidate_event && event_reference(candidate_event)
        decision = @decider.call(
          change_set_state: load_change_set_state(command.change_set_id),
          work_item_state: load_work_item_state(command.work_item_id),
          attempt_state: load_attempt_state(command.attempt_id),
          candidate:,
          candidate_event: candidate_reference,
          command:,
          completed_at: prepared.completed_at
        )
        return decision if decision.failure?

        persisted = persist_domain_plan(
          decision.value!,
          command:,
          candidate_event: candidate_reference,
          repository_id: candidate.repository_id,
          prepared:,
          caused_by:
        )
        completion_fact = decision.value!.events.fetch(2)
        completion = @completion_builder.work_item_complete(
          command:,
          completion: completion_fact,
          input_digest: prepared.input_digest,
          persisted_events: persisted,
          completed_at: prepared.completed_at
        )
        persist_completion(
          completion,
          command:,
          event_id: prepared.completion_event_id,
          caused_by:
        )

        Success(completion)
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
        event = @event_store.read(
          @stream_factory.command(command_id),
          EventQueries::COMMAND_COMPLETION
        ).first
        event && load_event(event)
      end

      def load_change_set_state(change_set_id)
        events = @event_store.read(
          @stream_factory.change_set(change_set_id),
          EventQueries::CHANGE_SET_FOR_WORK_ITEM_COMPLETION
        ).map { load_event(_1) }
        Domain::ChangeSets::State.reduce(events)
      end

      def load_work_item_state(work_item_id)
        events = @event_store.read(
          @stream_factory.work_item(work_item_id),
          EventQueries::WORK_ITEM_FOR_COMPLETION
        ).map { load_event(_1) }
        Domain::WorkItems::State.reduce(events)
      end

      def load_attempt_state(attempt_id)
        stream = @stream_factory.attempt(attempt_id)
        membership = @event_store.read(stream, EventQueries::ATTEMPT_FOR_WORK_ITEM_COMPLETION)
        lifecycle = @event_store.read_grouped(
          stream,
          EventQueries::ATTEMPT_LATEST_WRITE_SET_LIFECYCLE
        )
        events = SpecificStreamEventSequence.merge(membership, lifecycle.reverse)
        Domain::Attempts::State.reduce(events.map { load_event(_1) })
      end

      def load_candidate_event(candidate_id)
        @event_store.read(
          @stream_factory.candidate(candidate_id),
          EventQueries::CANDIDATE_FOR_WORK_ITEM_COMPLETION
        ).first
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def persist_domain_plan(plan, command:, candidate_event:, repository_id:, prepared:, caused_by:)
        work_item_stream = @stream_factory.work_item(command.work_item_id)
        attempt_stream = @stream_factory.attempt(command.attempt_id)
        verify_event_plan!(
          plan,
          command:,
          candidate_event:,
          work_item_stream:,
          attempt_stream:,
          completed_at: prepared.completed_at
        )
        metadata = command_metadata(command)

        plan.writes.zip(prepared.domain_event_ids).map do |write, event_id|
          physical = @event_factory.build!(
            event: write.event,
            event_id:,
            metadata:,
            markers: event_markers(command, repository_id:),
            caused_by:
          )
          @event_store.append(write.stream, [ physical ]).sole
        end
      end

      def verify_event_plan!(plan, **attributes)
        result = @event_plan_contract.call(plan:, **attributes)
        return if result.success?

        raise InvalidWorkItemCompletionEventPlan, result.errors.to_h.inspect
      end

      def event_markers(command, repository_id:)
        [
          "change-set:#{command.change_set_id}",
          "work-item:#{command.work_item_id}",
          "attempt:#{command.attempt_id}",
          "candidate:#{command.candidate_id}",
          "repository:#{repository_id}",
          "command:#{command.command_id}"
        ]
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
          policy_version: Domain::WorkItems::Complete::RULE_VERSION
        )
      end

      def event_reference(event)
        EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end
    end
  end
end
