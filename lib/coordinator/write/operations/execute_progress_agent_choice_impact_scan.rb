# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteProgressAgentChoiceImpactScan
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        loader: AgentChoiceImpacts::ScanLoader.new(event_store:),
        decider: Domain::AgentChoiceImpacts::ProgressScan.new,
        retry_policy: AgentChoiceImpacts::ExpectedRevisionRetry.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        stream_factory: StreamFactory.new,
        progress_contract: Contracts::AgentChoiceImpactScanProgress.new,
        invocation_contract: Contracts::AgentChoiceImpactScanProgressInvocation.new,
        command_contract: Contracts::AgentChoiceImpactScanProgressCommand.new,
        event_plan_contract: Contracts::AgentChoiceImpactScanProgressEventPlan.new
      )
        @event_store = event_store
        @loader = loader
        @decider = decider
        @retry_policy = retry_policy
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @stream_factory = stream_factory
        @progress_contract = progress_contract
        @invocation_contract = invocation_contract
        @command_contract = command_contract
        @event_plan_contract = event_plan_contract
      end

      def call(invocation)
        verify_input!(invocation)
        preparation = AgentChoiceImpactScanProgressPreparationV1.new(
          progressed_at: @clock.now,
          event_id: @id_generator.uuid_v7
        )

        @retry_policy.call(scan_id: invocation.command.scan_id) do
          execute_attempt(invocation:, preparation:)
        end
      end

      private

      def execute_attempt(invocation:, preparation:)
        command = invocation.command
        snapshot = @loader.call(command.scan_id)
        decision = @decider.call(
          state: snapshot.state,
          command:,
          progressed_at: preparation.progressed_at
        )
        return decision if decision.failure?

        plan = decision.value!
        stream = @stream_factory.agent_choice_impact_scan(command.scan_id)
        verify_event_plan!(plan, command:, expected_stream: stream)
        event = @event_factory.build!(
          event: plan.events.sole,
          event_id: preparation.event_id,
          metadata: metadata(command),
          markers: markers(command),
          caused_by: invocation.caused_by
        )
        persisted = @event_store.append(
          stream,
          [ event ],
          expected_revision: snapshot.latest_revision
        ).sole

        Success(persisted)
      end

      def verify_input!(invocation)
        results = [
          @progress_contract.call(command: invocation.command),
          @invocation_contract.call(invocation:),
          @command_contract.call(command: invocation.command)
        ]
        errors = results.filter_map { _1.errors.to_h if _1.failure? }
        return if errors.empty?

        raise ArgumentError, "impact scan progress violates its dry-rb contracts: #{errors.inspect}"
      end

      def verify_event_plan!(plan, command:, expected_stream:)
        result = @event_plan_contract.call(plan:, command:, expected_stream:)
        return if result.success?

        raise ArgumentError, "impact scan progress plan violates its dry-rb contract: #{result.errors.to_h.inspect}"
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

      def markers(command)
        [
          "impact-scan:#{command.scan_id}",
          "command:#{command.command_id}"
        ].freeze
      end
    end
  end
end
