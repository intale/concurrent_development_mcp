# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteProgressCandidateImpactPairScan
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        exact_loader: CandidateObligations::ExactEventLoader.new(event_store:),
        loader: CandidateObligationScans::PairScanLoader.new(event_store:),
        decider: Domain::CandidateObligationScans::ProgressPairScan.new,
        revision_guard: CandidateObligationScans::ExpectedRevisionGuard.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        stream_factory: StreamFactory.new,
        input_contract: Contracts::CandidateImpactPairScanProgress.new,
        event_plan_contract: Contracts::CandidateImpactPairScanProgressEventPlan.new
      )
        @event_store = event_store
        @exact_loader = exact_loader
        @loader = loader
        @decider = decider
        @revision_guard = revision_guard
        @id_generator = id_generator
        @event_factory = event_factory
        @stream_factory = stream_factory
        @input_contract = input_contract
        @event_plan_contract = event_plan_contract
      end

      def call(invocation)
        verify_input!(invocation)
        preparation = CandidateObligationScans::ProgressPreparationV1.new(
          event_id: @id_generator.uuid_v7,
          correlation_id: invocation.caused_by&.correlation_id || @id_generator.uuid_v7
        )

        @revision_guard.call(scan_id: invocation.command.scan_id) do
          execute_attempt(invocation:, preparation:)
        end
      end

      private

      def execute_attempt(invocation:, preparation:)
        command = invocation.command
        @exact_loader.call(invocation.checkpoint_reference)
        snapshot = @loader.call(command.scan_id)
        decision = @decider.call(state: snapshot.state, command:)
        return decision if decision.failure?

        plan = decision.value!
        stream = @stream_factory.candidate_impact_pair_scan(command.scan_id)
        verify_event_plan!(plan, command:, state: snapshot.state, expected_stream: stream)
        physical = @event_factory.build!(
          event: plan.events.sole,
          event_id: preparation.event_id,
          metadata: metadata(plan.events.sole, command),
          markers: markers(command),
          caused_by: invocation.caused_by,
          correlation_id: preparation.correlation_id
        )
        persisted = @event_store.append(
          stream,
          [ physical ],
          expected_revision: snapshot.latest_revision
        ).sole

        Success(persisted)
      end

      def verify_input!(invocation)
        result = @input_contract.call(invocation:)
        return if result.success?

        raise ArgumentError, "pair scan progress violates its dry-rb contract: #{result.errors.to_h.inspect}"
      end

      def verify_event_plan!(plan, command:, state:, expected_stream:)
        result = @event_plan_contract.call(plan:, command:, state:, expected_stream:)
        return if result.success?

        raise ArgumentError, "pair scan progress plan violates its dry-rb contract: #{result.errors.to_h.inspect}"
      end

      def metadata(event, command)
        common = {
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: event.is_a?(Events::CandidateImpactPairScanCompletedV2) ? nil : command.rule_version
        }
        Metadata::CandidateImpactPairScanV2.new(common.merge(index_policy_version: command.index_policy_version))
      end

      def markers(command)
        [
          "candidate-impact-pair-scan:#{command.scan_id}",
          "change-set:#{command.change_set_id}",
          "candidate-impact-direction:#{command.direction}",
          "command:#{command.command_id}"
        ].freeze
      end
    end
  end
end
