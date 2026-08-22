# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteProposeDecisionInterpretation < Dry::Operation
      TOOL_NAME = "decision_interpretation_propose"

      def initialize(
        event_store:,
        preparer: PrepareProposeDecisionInterpretation.new,
        decider: Domain::Interpretations::Propose.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandCompletionBuilder.new,
        event_plan_contract: Contracts::InterpretationProposalEventPlan.new
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
          preparation = prepare_logical_values(command)

          step @event_store.multiple { execute_attempt(command:, preparation:, caused_by:) }
        end
      end

      private

      def prepare_logical_values(command)
        InterpretationProposalPreparationV1.new(
          proposed_at: @clock.now,
          input_digest: @input_digest.decision_interpretation_propose(command),
          proposal_event_id: @id_generator.uuid_v7,
          clarification_event_id: @id_generator.uuid_v7,
          completion_event_id: @id_generator.uuid_v7
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        replay = replay_result(command:, input_digest: preparation.input_digest)
        return replay if replay

        state = load_state(command)
        decision = @decider.call(state:, command:, proposed_at: preparation.proposed_at)
        return decision if decision.failure?

        plan = apply_event_plan_contract(decision.value!, command)
        persisted_events = persist_domain_plan(
          plan,
          command:,
          preparation:,
          caused_by:
        )
        proposal = plan.events.first
        completion = @completion_builder.decision_interpretation_propose(
          command:,
          proposal:,
          input_digest: preparation.input_digest,
          persisted_events:,
          completed_at: preparation.proposed_at
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

      def load_state(command)
        source_event = @event_store.read_global_marked(
          EventQueries.guidance_message(message_marker(command.source_message_id))
        ).first
        proposal = @event_store.read_global_marked(
          EventQueries.interpretation_proposal(interpretation_marker(command.interpretation_id))
        ).first

        Domain::Interpretations::State.new(
          source: source_event && build_source(source_event),
          proposal_exists: !proposal.nil?
        )
      end

      def build_source(event)
        payload = load_event(event)
        Interpretations::GuidanceSourceEvidenceV1.new(
          message_id: payload.message_id,
          text: payload.text,
          anchors: payload.anchors,
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

        raise ArgumentError, "interpretation plan violates its dry-rb contract: #{result.errors.to_h.inspect}"
      end

      def persist_domain_plan(plan, command:, preparation:, caused_by:)
        event_ids = [ preparation.proposal_event_id, preparation.clarification_event_id ]
        persisted = plan.events.each_with_index.map do |event, index|
          @event_factory.build!(
            event:,
            event_id: event_ids.fetch(index),
            metadata: command_metadata(command),
            markers: markers_for(event, command),
            caused_by:
          )
        end

        @event_store.append(@stream_factory.interpretation(command.source_message_id), persisted)
      end

      def markers_for(event, command)
        common = [ message_marker(command.source_message_id), "command:#{command.command_id}" ]
        identity = if event.is_a?(Events::DecisionInterpretationProposedV1)
                     interpretation_marker(command.interpretation_id)
        else
                     "interpretation-lifecycle:#{command.interpretation_id}"
        end

        common + [ identity ]
      end

      def persist_completion(completion, command:, event_id:, caused_by:)
        persisted = @event_factory.build!(
          event: completion,
          event_id:,
          metadata: command_metadata(command),
          markers: [ "command:#{command.command_id}" ],
          caused_by:
        )

        @event_store.append(@stream_factory.command(command.command_id), [ persisted ])
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

      def command_metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: "interpretation-proposal/v1"
        )
      end
    end
  end
end
