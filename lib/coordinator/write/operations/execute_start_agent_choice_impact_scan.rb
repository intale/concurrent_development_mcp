# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteStartAgentChoiceImpactScan
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        source_builder: AgentChoiceImpacts::DecisionChangeEvidenceBuilder.new(event_store:),
        loader: AgentChoiceImpacts::ScanLoader.new(event_store:),
        decider: Domain::AgentChoiceImpacts::StartScan.new,
        retry_policy: AgentChoiceImpacts::ExpectedRevisionRetry.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        stream_factory: StreamFactory.new,
        invocation_contract: Contracts::AgentChoiceImpactScanInvocation.new,
        command_contract: Contracts::AgentChoiceImpactScanStartCommand.new,
        event_plan_contract: Contracts::AgentChoiceImpactScanStartEventPlan.new
      )
        @event_store = event_store
        @source_builder = source_builder
        @loader = loader
        @decider = decider
        @retry_policy = retry_policy
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
        preparation = AgentChoiceImpactScanStartPreparationV1.new(
          started_at: @clock.now,
          event_id: @id_generator.uuid_v7
        )

        @retry_policy.call(scan_id: invocation.command.scan_id) do
          execute_attempt(invocation:, preparation:)
        end
      end

      private

      def execute_attempt(invocation:, preparation:)
        command = invocation.command
        source = @source_builder.call(invocation.source_event)
        return source if source.failure?

        decision_change = source.value!
        verify_command!(command, decision_change)
        snapshot = @loader.call(command.scan_id)
        decision = @decider.call(
          state: snapshot.state,
          command:,
          decision_change:,
          started_at: preparation.started_at
        )
        return decision if decision.failure?

        plan = decision.value!
        stream = @stream_factory.agent_choice_impact_scan(command.scan_id)
        verify_event_plan!(plan, command:, decision_change:, expected_stream: stream)
        event = @event_factory.build!(
          event: plan.events.sole,
          event_id: preparation.event_id,
          metadata: metadata(command),
          markers: markers(command, decision_change),
          caused_by: invocation.caused_by
        )
        expected_revision = snapshot.latest_revision || :no_stream
        persisted = @event_store.append(stream, [ event ], expected_revision:).sole

        Success(persisted)
      end

      def verify_invocation!(invocation)
        result = @invocation_contract.call(invocation:)
        return if result.success?

        raise ArgumentError, "impact scan invocation violates its dry-rb contract: #{result.errors.to_h.inspect}"
      end

      def verify_command!(command, decision_change)
        result = @command_contract.call(command:, decision_change:)
        return if result.success?

        raise ArgumentError, "impact scan command violates its dry-rb contract: #{result.errors.to_h.inspect}"
      end

      def verify_event_plan!(plan, command:, decision_change:, expected_stream:)
        result = @event_plan_contract.call(plan:, command:, decision_change:, expected_stream:)
        return if result.success?

        raise ArgumentError, "impact scan start plan violates its dry-rb contract: #{result.errors.to_h.inspect}"
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

      def markers(command, decision_change)
        [
          "impact-scan:#{command.scan_id}",
          "decision:#{decision_change.decision_id}",
          "decision-change:#{decision_change.source_event.event_id}",
          "command:#{command.command_id}"
        ].freeze
      end
    end
  end
end
