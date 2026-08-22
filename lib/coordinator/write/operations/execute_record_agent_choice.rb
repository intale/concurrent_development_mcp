# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteRecordAgentChoice < Dry::Operation
      TOOL_NAME = "agent_choice_record"
      MAXIMUM_PARTITIONS = 8
      MAXIMUM_ACTIVE_DECISIONS = 32

      def initialize(
        event_store:,
        preparer: PrepareRecordAgentChoice.new,
        partition_selector: DecisionContexts::PartitionSelector.new,
        resolver: DecisionContexts::Resolver.new,
        context_builder: DecisionContexts::Builder.new,
        decider: Domain::AgentChoices::Record.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandCompletionBuilder.new,
        event_plan_contract: Contracts::AgentChoiceEventPlan.new
      )
        @event_store = event_store
        @preparer = preparer
        @partition_selector = partition_selector
        @resolver = resolver
        @context_builder = context_builder
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
        AgentChoicePreparationV1.new(
          recorded_at: @clock.now,
          input_digest: @input_digest.agent_choice_record(command),
          recorded_event_id: @id_generator.uuid_v7,
          accepted_event_id: @id_generator.uuid_v7,
          completion_event_id: @id_generator.uuid_v7
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        replay = replay_result(command:, input_digest: preparation.input_digest)
        return replay if replay

        state = load_state(command, preparation)
        return state if state.failure?

        recorded_event = future_recorded_reference(command, preparation.recorded_event_id)
        decision = @decider.call(
          state: state.value!,
          command:,
          recorded_at: preparation.recorded_at,
          recorded_event:
        )
        return decision if decision.failure?

        plan = apply_event_plan_contract(
          decision.value!,
          command:,
          context: state.value!.current_context,
          recorded_event:
        )
        persisted_events = persist_domain_plan(plan, command:, preparation:, caused_by:)
        acceptance = plan.events.fetch(1)
        completion = @completion_builder.agent_choice_record(
          command:,
          acceptance:,
          input_digest: preparation.input_digest,
          persisted_events:,
          completed_at: preparation.recorded_at
        )
        persist_completion(
          completion,
          command:,
          event_id: preparation.completion_event_id,
          caused_by:
        )

        Success(completion)
      end

      def load_state(command, preparation)
        partitions = @partition_selector.call(command.context)
        return context_limit(partition_count: partitions.length, active_decision_count: 0) if partitions.length > MAXIMUM_PARTITIONS

        observations = load_observations(partitions)
        return observations if observations.failure?

        heads = exact_heads(observations.value!)
        if heads.length > MAXIMUM_ACTIVE_DECISIONS
          return context_limit(
            partition_count: partitions.length,
            active_decision_count: heads.length
          )
        end

        decisions = load_decisions(heads)
        return decisions if decisions.failure?

        resolution = @resolver.call(
          context: command.context,
          observations: observations.value!,
          decisions: decisions.value!,
          resolved_at: preparation.recorded_at
        )
        current_context = @context_builder.call(
          context: command.context,
          observations: observations.value!,
          resolution:,
          resolved_at: preparation.recorded_at
        )
        Success(
          Domain::AgentChoices::State.new(
            attempt: load_attempt_state(command.context.attempt_id),
            existing_choice: load_existing_choice(command.choice_id),
            current_context:,
            resolution:
          )
        )
      end

      def load_observations(partitions)
        observations = []
        partitions.each do |partition|
          event = @event_store.read_grouped(
            @stream_factory.decision_partition(partition.partition_id),
            EventQueries::DECISION_PARTITION_LATEST
          ).first
          unless event
            observations << DecisionContexts::PartitionObservationV1.new(
              partition:,
              partition_revision: nil,
              event: nil,
              active_decisions: []
            )
            next
          end

          payload = load_event(event)
          invalid = invalid_partition_snapshot(partition, event, payload)
          return invalid if invalid

          observations << DecisionContexts::PartitionObservationV1.new(
            partition:,
            partition_revision: event.stream_revision,
            event: event_reference(event),
            active_decisions: payload.active_decisions
          )
        end
        Success(observations.freeze)
      end

      def invalid_partition_snapshot(partition, event, payload)
        heads = payload.active_decisions
        unique_and_ordered = heads.map(&:decision_id).uniq.length == heads.length &&
                             heads == heads.sort_by { _1.decision_id.b }
        exact_heads = heads.all? do |head|
          head.decision_revision == head.event.stream_revision &&
            head.event.stream_context == "HumanGuidance" &&
            head.event.stream_name == "Decision" &&
            head.event.stream_id == head.decision_id
        end
        return if payload.partition == partition &&
                  payload.partition_revision == event.stream_revision &&
                  unique_and_ordered && exact_heads

        Failure(
          OutcomeError.new(
            code: :decision_partition_state_invalid,
            message: "DecisionPartition snapshot violates its authoritative invariant",
            details: {
              partition_id: partition.partition_id,
              stream_revision: event.stream_revision,
              snapshot: payload.to_h
            }
          )
        )
      end

      def exact_heads(observations)
        observations.flat_map(&:active_decisions)
          .uniq { [ _1.decision_id, _1.event.event_id ] }
          .sort_by { [ _1.decision_id.b, _1.event.event_id.b ] }
      end

      def load_decisions(heads)
        decisions = []
        heads.each do |head|
          decision = load_current_decision(head)
          return decision if decision.failure?

          decisions << decision.value!
        end
        Success(decisions.freeze)
      end

      def load_current_decision(expected_head)
        events = @event_store.read_grouped(
          @stream_factory.decision(expected_head.decision_id),
          EventQueries::DECISION_CORRECTION_STATE
        )
        recorded_event = events.find { _1.type == "DecisionRecorded" }
        activated_event = events.find { _1.type == "DecisionActivated" }
        correction_event = events.find { _1.type == "DecisionDefinitionCorrected" }
        return invalid_decision_head(expected_head, nil) unless recorded_event && activated_event

        recorded = load_event(recorded_event)
        activation = load_event(activated_event)
        correction = correction_event && load_event(correction_event)
        head_event = correction_event || activated_event
        current = Decisions::DecisionCurrentStateV1.new(
          decision_id: expected_head.decision_id,
          definition: correction ? correction.definition : recorded.definition,
          head: Decisions::DecisionHeadV1.new(
            decision_id: expected_head.decision_id,
            decision_revision: head_event.stream_revision,
            event: event_reference(head_event)
          ),
          slot: correction ? correction.slot : activation.slot,
          partitions: correction ? correction.partitions : activation.partitions
        )
        return Success(current) if current.head == expected_head

        invalid_decision_head(expected_head, current.head)
      end

      def invalid_decision_head(expected, current)
        Failure(
          OutcomeError.new(
            code: :decision_partition_state_invalid,
            message: "DecisionPartition does not reference the exact current Decision head",
            details: {
              decision_id: expected.decision_id,
              expected_head: expected.to_h,
              current_head: current&.to_h
            }
          )
        )
      end

      def load_attempt_state(attempt_id)
        events = @event_store.read(
          @stream_factory.attempt(attempt_id),
          EventQueries::ATTEMPT_FOR_AGENT_CHOICE
        ).map { load_event(_1) }
        Domain::Attempts::State.reduce(events)
      end

      def load_existing_choice(choice_id)
        event = @event_store.read(
          @stream_factory.agent_choice(choice_id),
          EventQueries::AGENT_CHOICE_EXISTENCE
        ).first
        event && event_reference(event)
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
        event && load_event(event)
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def apply_event_plan_contract(plan, command:, context:, recorded_event:)
        result = @event_plan_contract.call(
          plan:,
          command:,
          context:,
          recorded_event:,
          expected_stream: @stream_factory.agent_choice(command.choice_id)
        )
        return plan if result.success?

        raise ArgumentError, "agent choice plan violates its dry-rb contract: #{result.errors.to_h.inspect}"
      end

      def persist_domain_plan(plan, command:, preparation:, caused_by:)
        assessment = plan.events.fetch(1).assessment
        event_ids = [ preparation.recorded_event_id, preparation.accepted_event_id ]
        events = plan.events.zip(event_ids).map do |payload, event_id|
          @event_factory.build!(
            event: payload,
            event_id:,
            metadata: command_metadata(command),
            markers: event_markers(command, assessment),
            caused_by:
          )
        end
        @event_store.append(@stream_factory.agent_choice(command.choice_id), events)
      end

      def event_markers(command, assessment)
        [
          "choice:#{command.choice_id}",
          "choice-type:#{command.choice_type}",
          "attempt:#{command.context.attempt_id}",
          "work-item:#{command.context.work_item_id}",
          "change-set:#{command.context.change_set_id}",
          "repository:#{command.context.repository_id}",
          "command:#{command.command_id}"
        ] + assessment.based_on_decisions.map { "decision:#{_1.decision_id}" }
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
          policy_version: "testing-framework-resolution/v1"
        )
      end

      def future_recorded_reference(command, event_id)
        EventReference.new(
          event_id:,
          type: "AgentChoiceRecorded",
          stream_context: "AgentGovernance",
          stream_name: "AgentChoice",
          stream_id: command.choice_id,
          stream_revision: 0
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

      def context_limit(partition_count:, active_decision_count:)
        Failure(
          OutcomeError.new(
            code: :decision_context_limit_reached,
            message: "Authoritative Decision context exceeds the bounded resolver limits",
            details: {
              partition_count:,
              maximum_partition_count: MAXIMUM_PARTITIONS,
              active_decision_count:,
              maximum_active_decision_count: MAXIMUM_ACTIVE_DECISIONS
            }
          )
        )
      end
    end
  end
end
