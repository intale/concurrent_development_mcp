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
          event_ids: Array.new(2) { @id_generator.uuid_v7 },
          correlation_id: invocation.caused_by&.correlation_id || @id_generator.uuid_v7
        )

        @event_store.multiple do
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
          decision_change:
        )
        return decision if decision.failure?

        plan = decision.value!
        stream = @stream_factory.agent_choice_impact_scan(command.scan_id)
        verify_event_plan!(plan, command:, decision_change:, expected_stream: stream)
        events = physical_events(
          plan.events,
          preparation:,
          command:,
          decision_change:,
          caused_by: invocation.caused_by
        )
        persisted = @event_store.append(stream, events)

        Success(persisted.first)
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

      def physical_events(events, preparation:, command:, decision_change:, caused_by:)
        parent = caused_by
        events.zip(preparation.event_ids).map do |event, event_id|
          physical = @event_factory.build!(
            event:,
            event_id:,
            metadata: metadata(event, command),
            markers: markers(command, decision_change, event),
            caused_by: parent,
            correlation_id: preparation.correlation_id
          )
          parent = physical
          physical
        end
      end

      def metadata(event, command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: event.is_a?(Events::AgentChoiceImpactScanSourceLinkedV1) ? nil : command.policy_version
        )
      end

      def markers(command, decision_change, event)
        values = [
          "impact-scan:#{command.scan_id}",
          "decision:#{decision_change.decision_id}",
          "decision-change:#{decision_change.source_event.event_id}",
          "command:#{command.command_id}"
        ]
        values << "source-role:#{event.role}" if event.is_a?(Events::AgentChoiceImpactScanSourceLinkedV1)
        values.freeze
      end
    end
  end
end
