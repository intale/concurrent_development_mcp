# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteAssessAgentChoiceDecisionImpact
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        source_builder: AgentChoiceImpacts::DecisionChangeEvidenceBuilder.new(event_store:),
        choice_loader: AgentChoiceImpacts::ChoiceLoader.new(event_store:),
        assessment_loader: AgentChoiceImpacts::AssessmentLoader.new(event_store:),
        attempt_loader: AgentChoiceImpacts::AttemptLoader.new(event_store:),
        reconstructor: AgentChoiceImpacts::HistoricalContextReconstructor.new(event_store:),
        identity_builder: AgentChoiceImpacts::AssessmentIdentityBuilder.new,
        decider: Domain::AgentChoiceImpacts::Assess.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        stream_factory: StreamFactory.new,
        invocation_contract: Contracts::AgentChoiceImpactAssessmentInvocation.new,
        command_contract: Contracts::AgentChoiceImpactAssessmentCommand.new,
        event_plan_contract: Contracts::AgentChoiceImpactAssessmentEventPlan.new
      )
        @event_store = event_store
        @source_builder = source_builder
        @choice_loader = choice_loader
        @assessment_loader = assessment_loader
        @attempt_loader = attempt_loader
        @reconstructor = reconstructor
        @identity_builder = identity_builder
        @decider = decider
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @stream_factory = stream_factory
        @invocation_contract = invocation_contract
        @command_contract = command_contract
        @event_plan_contract = event_plan_contract
      end

      def call(invocation)
        verify_invocation!(invocation)
        verify_command!(invocation.command, invocation.command.decision_change)
        preparation = AgentChoiceImpactAssessmentPreparationV1.new(
          assessed_at: @clock.now,
          assessment_event_id: @id_generator.uuid_v7,
          invalidation_event_id: @id_generator.uuid_v7
        )

        @event_store.multiple do
          execute_attempt(invocation:, preparation:)
        end
      end

      private

      def execute_attempt(invocation:, preparation:)
        command = invocation.command
        replay = @assessment_loader.call(command)
        return Success(replay) if replay

        authoritative_change = load_authoritative_change(command.decision_change.source_event)
        verify_command!(command, authoritative_change)
        choice = @choice_loader.call(
          choice_id: command.choice_id,
          accepted_choice: command.accepted_choice
        )
        reconstruction = @reconstructor.call(
          recorded_choice: choice.recorded,
          decision_change: authoritative_change
        )
        state = Domain::AgentChoiceImpacts::AssessmentState.new(
          choice:,
          attempt: @attempt_loader.call(choice.recorded),
          reconstruction:
        )
        assessment_reference = future_assessment_reference(command, preparation.assessment_event_id)
        decision = @decider.call(
          state:,
          command:,
          assessed_at: preparation.assessed_at,
          assessment_event: assessment_reference
        )
        plan = decision.value!
        verify_event_plan!(plan, state:, command:, assessment_reference:)
        persist(plan, state:, command:, invocation:, preparation:)
      end

      def load_authoritative_change(source_reference)
        source_event = read_reference(source_reference)
        unless source_event
          raise AgentChoiceImpacts::InvalidHistory.new(
            reason: "decision_change_source_missing",
            evidence: { source_event: source_reference.to_h }
          )
        end
        result = @source_builder.call(source_event)
        return result.value! if result.success?

        raise AgentChoiceImpacts::InvalidHistory.new(
          reason: "decision_change_source_invalid",
          evidence: result.failure.details
        )
      end

      def read_reference(reference)
        event = @event_store.read_at(
          StreamReference.new(
            context: reference.stream_context,
            stream_name: reference.stream_name,
            stream_id: reference.stream_id
          ),
          reference.stream_revision
        )
        event if event && event_reference(event) == reference
      end

      def verify_invocation!(invocation)
        result = @invocation_contract.call(invocation:)
        return if result.success?

        raise ArgumentError, "impact assessment invocation violates its dry-rb contract: #{result.errors.to_h.inspect}"
      end

      def verify_command!(command, authoritative_change)
        expected_identity = @identity_builder.call(
          accepted_choice: command.accepted_choice,
          decision_change: authoritative_change.source_event,
          policy_version: command.policy_version
        )
        result = @command_contract.call(
          command:,
          authoritative_change:,
          expected_identity:
        )
        return if result.success?

        raise ArgumentError, "impact assessment command violates its dry-rb contract: #{result.errors.to_h.inspect}"
      end

      def verify_event_plan!(plan, state:, command:, assessment_reference:)
        result = @event_plan_contract.call(
          plan:,
          state:,
          command:,
          assessment_event: assessment_reference,
          impact_stream: @stream_factory.agent_choice_impact(command.assessment_id),
          choice_stream: @stream_factory.agent_choice(command.choice_id)
        )
        return if result.success?

        raise ArgumentError, "impact assessment plan violates its dry-rb contract: #{result.errors.to_h.inspect}"
      end

      def persist(plan, state:, command:, invocation:, preparation:)
        physical_events = plan.events.each_with_index.map do |event, index|
          @event_factory.build!(
            event:,
            event_id: index.zero? ? preparation.assessment_event_id : preparation.invalidation_event_id,
            metadata: metadata(command),
            markers: index.zero? ? assessment_markers(command, state) : invalidation_markers(command, state),
            caused_by: invocation.caused_by
          )
        end
        persisted_assessment = @event_store.append(
          @stream_factory.agent_choice_impact(command.assessment_id),
          [ physical_events.fetch(0) ]
        ).sole
        if physical_events.length == 2
          @event_store.append(
            @stream_factory.agent_choice(command.choice_id),
            [ physical_events.fetch(1) ]
          )
        end

        Success(persisted_assessment)
      end

      def metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: command.policy_version
        )
      end

      def assessment_markers(command, state)
        [
          "impact-assessment:#{command.assessment_id}",
          "choice:#{command.choice_id}",
          "attempt:#{state.choice.recorded.context.attempt_id}",
          "decision:#{command.decision_change.decision_id}",
          "decision-change:#{command.decision_change.source_event.event_id}",
          "command:#{command.command_id}"
        ].freeze
      end

      def invalidation_markers(command, state)
        context = state.choice.recorded.context
        markers = assessment_markers(command, state) + [
          "choice-type:#{state.choice.recorded.choice_type}",
          "work-item:#{context.work_item_id}",
          "change-set:#{context.change_set_id}",
          "repository:#{context.repository_id}"
        ]
        markers.concat(
          state.choice.recorded.decision_context.document.partitions.map do |observation|
            "decision-partition:#{observation.partition.partition_id}"
          end
        ).uniq.freeze
      end

      def future_assessment_reference(command, event_id)
        EventReference.new(
          event_id:,
          type: "AgentChoiceImpactAssessed",
          stream_context: "AgentGovernance",
          stream_name: "AgentChoiceImpact",
          stream_id: command.assessment_id,
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
    end
  end
end
