# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteAdjudicateDecisionInterpretation < Dry::Operation
      TOOL_NAME = "decision_interpretation_adjudicate"

      def initialize(
        event_store:,
        preparer: PrepareAdjudicateDecisionInterpretation.new,
        decider: Domain::Interpretations::Adjudicate.new,
        slot_builder: Interpretations::InterpretationSlotBuilder.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandCompletionBuilder.new,
        event_plan_contract: Contracts::InterpretationAdjudicationEventPlan.new
      )
        @event_store = event_store
        @preparer = preparer
        @decider = decider
        @slot_builder = slot_builder
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
        InterpretationAdjudicationPreparationV1.new(
          adjudicated_at: @clock.now,
          input_digest: @input_digest.decision_interpretation_adjudicate(command),
          lifecycle_event_id: @id_generator.uuid_v7,
          completion_event_id: @id_generator.uuid_v7
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        replay = replay_result(command:, input_digest: preparation.input_digest)
        return replay if replay

        proposal_event = load_proposal(command.interpretation_id)
        proposal = proposal_event && load_event(proposal_event)
        slot = proposal && @slot_builder.call(proposal)
        state = load_state(command:, proposal_event:, proposal:, slot:)
        decision = @decider.call(
          state:,
          command:,
          slot:,
          adjudicated_at: preparation.adjudicated_at
        )
        return decision if decision.failure?

        plan = apply_event_plan_contract(decision.value!, command)
        persisted_events = persist_domain_plan(
          plan,
          command:,
          slot:,
          event_id: preparation.lifecycle_event_id,
          caused_by:
        )
        completion = @completion_builder.decision_interpretation_adjudicate(
          command:,
          slot:,
          input_digest: preparation.input_digest,
          persisted_events:,
          completed_at: preparation.adjudicated_at
        )
        persist_completion(
          completion,
          command:,
          event_id: preparation.completion_event_id,
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
        event && load_event(event)
      end

      def load_proposal(interpretation_id)
        @event_store.read_global_marked(
          EventQueries.interpretation_proposal(interpretation_marker(interpretation_id))
        ).first
      end

      def load_state(command:, proposal_event:, proposal:, slot:)
        terminal_event = @event_store.read_global_marked(
          EventQueries.interpretation_terminal(lifecycle_marker(command.interpretation_id))
        ).first
        slot_event = if command.action == "accept" && slot
                       @event_store.read_global_marked(
                         EventQueries.interpretation_slot_acceptance(slot.compound_marker.marker)
                       ).first
        end

        Domain::Interpretations::AdjudicationState.new(
          proposal: proposal && Interpretations::InterpretationProposalEvidenceV1.new(
            proposal:,
            event: event_reference(proposal_event)
          ),
          terminal: terminal_event && terminal_evidence(terminal_event),
          slot_acceptance: slot_event && terminal_evidence(slot_event)
        )
      end

      def terminal_evidence(event)
        payload = load_event(event)
        Interpretations::InterpretationTerminalEvidenceV1.new(
          status: payload.is_a?(Events::DecisionInterpretationAcceptedV1) ? "accepted" : "rejected",
          interpretation_id: payload.interpretation_id,
          event: event_reference(event)
        )
      end

      def apply_event_plan_contract(plan, command)
        result = @event_plan_contract.call(
          plan:,
          command:,
          expected_stream: @stream_factory.interpretation(command.source_message_id)
        )
        return plan if result.success?

        raise ArgumentError, "interpretation adjudication plan violates its dry-rb contract: #{result.errors.to_h.inspect}"
      end

      def persist_domain_plan(plan, command:, slot:, event_id:, caused_by:)
        event = @event_factory.build!(
          event: plan.events.sole,
          event_id:,
          metadata: command_metadata(command),
          markers: markers_for(command, slot),
          caused_by:
        )

        @event_store.append(@stream_factory.interpretation(command.source_message_id), [ event ])
      end

      def markers_for(command, slot)
        markers = [
          message_marker(command.source_message_id),
          lifecycle_marker(command.interpretation_id),
          "command:#{command.command_id}"
        ]
        return markers unless command.action == "accept"

        markers + slot.compound_marker.components + [ slot.compound_marker.marker ]
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

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
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

      def message_marker(message_id)
        "message:#{message_id}"
      end

      def interpretation_marker(interpretation_id)
        "interpretation:#{interpretation_id}"
      end

      def lifecycle_marker(interpretation_id)
        "interpretation-lifecycle:#{interpretation_id}"
      end

      def command_metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: "interpretation-adjudication/v1"
        )
      end
    end
  end
end
