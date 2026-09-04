# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteStartCandidateImpactPairScan
      include Dry::Monads[:result]

      CONSISTENCY_BOUNDARY = "candidate_impact_pair_scan_start_consistency"

      def initialize(
        event_store:,
        exact_loader: CandidateObligations::ExactEventLoader.new(event_store:),
        candidate_loader: CandidateObligations::CandidateEvidenceLoader.new(event_store:),
        policy_loader: CandidateObligations::ImpactPolicyLoader.new(event_store:),
        marker_builder: Candidates::ImpactIndexMarkerBuilder.new,
        loader: CandidateObligationScans::PairScanLoader.new(event_store:),
        decider: Domain::CandidateObligationScans::StartPairScan.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        stream_factory: StreamFactory.new,
        input_contract: Contracts::CandidateImpactPairScanStart.new,
        event_plan_contract: Contracts::CandidateImpactPairScanStartEventPlan.new
      )
        @event_store = event_store
        @exact_loader = exact_loader
        @candidate_loader = candidate_loader
        @policy_loader = policy_loader
        @marker_builder = marker_builder
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
        preparation = CandidateObligationScans::StartPreparationV1.new(
          observed_at: @clock.now,
          event_ids: Array.new(4) { @id_generator.uuid_v7 },
          correlation_id: invocation.caused_by&.correlation_id || @id_generator.uuid_v7
        )

        @event_store.multiple do
          execute_attempt(invocation:, preparation:)
        end
      end

      private

      def execute_attempt(invocation:, preparation:)
        command = invocation.command
        source = @exact_loader.call(invocation.source_reference)
        evidence = @candidate_loader.call(command.source_registration)
        verify_input!(invocation, evidence)
        policy = @policy_loader.call(
          policy_partition_event: command.policy_partition_event,
          policy_head: command.policy_head,
          change_set_id: command.change_set_id,
          observed_at: preparation.observed_at
        )
        index_evidence = Candidates::ImpactSurfaceEvidenceV2.new(candidate: evidence.candidate)
        routing_markers = @marker_builder.counterpart(
          evidence: index_evidence,
          surface: evidence.surface,
          direction: command.direction
        )
        snapshot = @loader.call(command.scan_id)
        ActiveSupport::Notifications.instrument(
          "coordinator.command_boundary",
          operation: CONSISTENCY_BOUNDARY,
          command_id: command.command_id,
          scan_id: command.scan_id,
          policy_partition_event_id: command.policy_partition_event.event_id,
          registry_revision: command.to_revision
        )
        decision = @decider.call(
          state: snapshot.state,
          command:,
          policy:,
          markers: routing_markers
        )
        return decision if decision.failure?

        plan = decision.value!
        stream = @stream_factory.candidate_impact_pair_scan(command.scan_id)
        verify_event_plan!(plan, command:, markers: routing_markers, expected_stream: stream)
        physical = physical_events(plan.events, command:, preparation:, caused_by: invocation.caused_by)
        persisted = @event_store.append(stream, physical)

        Success(persisted.first)
      end

      def verify_input!(invocation, evidence)
        result = @input_contract.call(invocation:, evidence:)
        return if result.success?

        raise ArgumentError, "pair scan input violates its dry-rb contract: #{result.errors.to_h.inspect}"
      end

      def verify_event_plan!(plan, command:, markers:, expected_stream:)
        result = @event_plan_contract.call(plan:, command:, markers:, expected_stream:)
        return if result.success?

        raise ArgumentError, "pair scan start plan violates its dry-rb contract: #{result.errors.to_h.inspect}"
      end

      def physical_events(events, command:, preparation:, caused_by:)
        parent = caused_by
        events.zip(preparation.event_ids).map do |event, event_id|
          physical = @event_factory.build!(
            event:,
            event_id:,
            metadata: metadata(event, command),
            markers: event_markers(command, event),
            caused_by: parent,
            correlation_id: preparation.correlation_id
          )
          parent = physical
          physical
        end
      end

      def metadata(event, command)
        common = {
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: event.is_a?(Events::CandidateImpactPairScanSourceLinkedV1) ? nil : command.rule_version
        }
        return EventMetadata.new(common) if event.is_a?(Events::CandidateImpactPairScanSourceLinkedV1)

        Metadata::CandidateImpactPairScanV2.new(common.merge(index_policy_version: command.index_policy_version))
      end

      def event_markers(command, event)
        values = [
          "candidate-impact-pair-scan:#{command.scan_id}",
          "change-set:#{command.change_set_id}",
          "candidate-impact-direction:#{command.direction}",
          "source-registration:#{command.source_registration.event_id}",
          "decision:#{command.policy_head.decision_id}",
          "command:#{command.command_id}"
        ]
        values << "source-role:#{event.role}" if event.is_a?(Events::CandidateImpactPairScanSourceLinkedV1)
        values.freeze
      end
    end
  end
end
