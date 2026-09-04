# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteProgressVerificationObligationValidityScan
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        exact_loader: CandidateObligations::ExactEventLoader.new(event_store:),
        loader: VerificationObligationValidityScans::ScanLoader.new(event_store:),
        decider: Domain::VerificationObligationValidityScans::Progress.new,
        revision_guard: VerificationObligationValidityScans::ExpectedRevisionGuard.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        stream_factory: StreamFactory.new,
        input_contract: Contracts::VerificationObligationValidityScanProgress.new,
        event_plan_contract: Contracts::VerificationObligationValidityScanProgressEventPlan.new
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
        preparation = VerificationObligationValidityScans::ProgressPreparationV1.new(
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
        stream = @stream_factory.verification_obligation_validity_scan(command.scan_id)
        verify_event_plan!(plan, snapshot.state, command, stream)
        physical = @event_factory.build!(
          event: plan.events.sole,
          event_id: preparation.event_id,
          metadata: metadata(plan.events.sole, command),
          markers: markers(command),
          caused_by: invocation.caused_by,
          correlation_id: preparation.correlation_id
        )
        Success(
          @event_store.append(stream, [ physical ], expected_revision: snapshot.latest_revision).sole
        )
      end

      def verify_input!(invocation)
        result = @input_contract.call(invocation:)
        return if result.success?

        raise ArgumentError, "validity scan progress violates its dry-rb contract: #{result.errors.to_h.inspect}"
      end

      def verify_event_plan!(plan, state, command, expected_stream)
        result = @event_plan_contract.call(
          plan:,
          state:,
          command:,
          expected_stream:
        )
        return if result.success?

        raise ArgumentError, "validity scan progress plan violates its dry-rb contract: #{result.errors.to_h.inspect}"
      end

      def metadata(event, command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: event.is_a?(Events::VerificationObligationValidityScanCompletedV2) ? nil : command.rule_version
        )
      end

      def markers(command)
        [
          "verification-obligation-validity-scan:#{command.scan_id}",
          "change-set:#{command.change_set_id}",
          "command:#{command.command_id}"
        ].freeze
      end
    end
  end
end
