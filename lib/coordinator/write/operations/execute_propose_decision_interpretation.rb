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
        completion_builder: CommandResultBuilder.new,
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
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        state = load_state(command)
        decision = @decider.call(state:, command:, proposed_at: preparation.proposed_at)
        return decision if decision.failure?

        plan = apply_event_plan_contract(decision.value!, command)
        persisted_events = persist_domain_plan(
          plan,
          command:,
          state:,
          preparation:,
          caused_by:
        )
        proposal = plan.events.first
        completion = @completion_builder.decision_interpretation_propose(
          command:,
          assessment: proposal.assessment,
          input_digest: preparation.input_digest,
          persisted_events:,
          completed_at: preparation.proposed_at
        )

        Success(completion)
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
        anchors = if payload.respond_to?(:anchors)
                    payload.anchors
                  else
                    load_guidance_anchors(payload.conversation_id, payload.message_id)
                  end
        Interpretations::GuidanceSourceEvidenceV1.new(
          message_id: payload.message_id,
          text: payload.text,
          anchors:,
          event: event_reference(event)
        )
      end

      def load_guidance_anchors(conversation_id, message_id)
        events = @event_store.read(
          @stream_factory.conversation(conversation_id),
          EventReadCriteria.new(
            event_types: [ "GuidanceMessageAnchored" ],
            maximum_count: 102,
            direction: :asc
          )
        ).map { load_event(_1) }.select { _1.message_id == message_id }
        repositories = events.filter_map { _1.anchor_id if _1.anchor_kind == "repository" }
        GuidanceAnchorsV1.new(
          repository_ids: repositories,
          change_set_id: anchor_id(events, "change_set"),
          work_item_id: anchor_id(events, "work_item"),
          attempt_id: anchor_id(events, "attempt")
        )
      end

      def anchor_id(events, kind)
        events.find { _1.anchor_kind == kind }&.anchor_id
      end

      def apply_event_plan_contract(plan, command)
        result = @event_plan_contract.call(
          plan:,
          command:,
          expected_stream: @stream_factory.interpretation(command.interpretation_id)
        )
        return plan if result.success?

        raise ArgumentError, "interpretation plan violates its dry-rb contract: #{result.errors.to_h.inspect}"
      end

      def persist_domain_plan(plan, command:, state:, preparation:, caused_by:)
        event_ids = [ preparation.proposal_event_id, preparation.clarification_event_id ]
        persisted = plan.events.each_with_index.map do |event, index|
          @event_factory.build!(
            event:,
            event_id: event_ids.fetch(index),
            metadata: event_metadata(event, command, source: state.source),
            markers: markers_for(event, command),
            caused_by:
          )
        end

        @event_store.append(@stream_factory.interpretation(command.interpretation_id), persisted)
      end

      def markers_for(event, command)
        common = [ message_marker(command.source_message_id), "command:#{command.command_id}" ]
        identity = if event.is_a?(Events::DecisionInterpretationProposedV2)
                     interpretation_marker(command.interpretation_id)
        else
                     "interpretation-lifecycle:#{command.interpretation_id}"
        end

        common + [ identity ]
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

      def event_metadata(event, command, source:)
        common = command_metadata(command).to_h
        return EventMetadata.new(common) unless event.is_a?(Events::DecisionInterpretationProposedV2)

        Metadata::InterpretationProposalV2.new(
          **common,
          classifier: command.classifier,
          scope_provenance: Domain::Interpretations::ScopeResolver.new.call(
            submitted_scope: command.proposed_decision.scope,
            source:
          ).provenance
        )
      end
    end
  end
end
