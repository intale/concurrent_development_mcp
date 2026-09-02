# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteStartCandidateImpactRegistrySweep
      include Dry::Monads[:result]

      CONSISTENCY_BOUNDARY = "candidate_impact_registry_sweep_start_consistency"

      def initialize(
        event_store:,
        exact_loader: CandidateObligations::ExactEventLoader.new(event_store:),
        policy_loader: CandidateObligations::ImpactPolicyLoader.new(event_store:),
        loader: CandidateObligationScans::RegistrySweepLoader.new(event_store:),
        decider: Domain::CandidateObligationScans::StartRegistrySweep.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        stream_factory: StreamFactory.new,
        input_contract: Contracts::CandidateImpactRegistrySweepStart.new,
        event_plan_contract: Contracts::CandidateImpactRegistrySweepStartEventPlan.new
      )
        @event_store = event_store
        @exact_loader = exact_loader
        @policy_loader = policy_loader
        @loader = loader
        @decider = decider
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @stream_factory = stream_factory
        @input_contract = input_contract
        @event_plan_contract = event_plan_contract
      end

      def call(invocation)
        verify_input!(invocation)
        preparation = CandidateObligationScans::StartPreparationV1.new(
          started_at: @clock.now,
          event_id: @id_generator.uuid_v7
        )

        @event_store.multiple do
          execute_attempt(invocation:, preparation:)
        end
      end

      private

      def execute_attempt(invocation:, preparation:)
        command = invocation.command
        source = @exact_loader.call(invocation.source_reference)
        policy = @policy_loader.call(
          policy_partition_event: command.policy_partition_event,
          policy_head: command.policy_head,
          change_set_id: command.change_set_id,
          observed_at: preparation.started_at
        )
        latest = latest_registry_revision(command.change_set_id)
        snapshot = @loader.call(command.scan_id)
        ActiveSupport::Notifications.instrument(
          "coordinator.command_boundary",
          operation: CONSISTENCY_BOUNDARY,
          command_id: command.command_id,
          scan_id: command.scan_id,
          policy_partition_event_id: command.policy_partition_event.event_id,
          registry_revision: latest
        )
        decision = @decider.call(
          state: snapshot.state,
          command:,
          policy:,
          latest_registry_revision: latest,
          started_at: preparation.started_at
        )
        return decision if decision.failure?

        plan = decision.value!
        stream = @stream_factory.candidate_impact_registry_sweep(command.scan_id)
        verify_event_plan!(plan, command:, expected_stream: stream)
        physical = @event_factory.build!(
          event: plan.events.sole,
          event_id: preparation.event_id,
          metadata: metadata(command),
          markers: markers(command),
          caused_by: invocation.caused_by
        )
        persisted = @event_store.append(stream, [ physical ]).sole

        Success(persisted)
      end

      def latest_registry_revision(change_set_id)
        @event_store.read_grouped(
          @stream_factory.candidate_impact_registry(change_set_id),
          EventQueries::CANDIDATE_IMPACT_REGISTRY_LATEST
        ).first&.stream_revision
      end

      def verify_input!(invocation)
        result = @input_contract.call(invocation:)
        return if result.success?

        raise ArgumentError, "registry sweep input violates its dry-rb contract: #{result.errors.to_h.inspect}"
      end

      def verify_event_plan!(plan, command:, expected_stream:)
        result = @event_plan_contract.call(plan:, command:, expected_stream:)
        return if result.success?

        raise ArgumentError, "registry sweep start plan violates its dry-rb contract: #{result.errors.to_h.inspect}"
      end

      def metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: command.rule_version
        )
      end

      def markers(command)
        [
          "candidate-impact-registry-sweep:#{command.scan_id}",
          "change-set:#{command.change_set_id}",
          "decision:#{command.policy_head.decision_id}",
          "policy-partition-event:#{command.policy_partition_event.event_id}",
          "command:#{command.command_id}"
        ].freeze
      end
    end
  end
end
