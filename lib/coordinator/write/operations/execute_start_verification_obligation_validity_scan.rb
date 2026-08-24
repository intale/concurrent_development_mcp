# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteStartVerificationObligationValidityScan
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        exact_loader: CandidateObligations::ExactEventLoader.new(event_store:),
        loader: VerificationObligationValidityScans::ScanLoader.new(event_store:),
        decider: Domain::VerificationObligationValidityScans::Start.new,
        retry_policy: VerificationObligationValidityScans::ExpectedRevisionRetry.new,
        identity_builder: VerificationObligationValidityScans::IdentityBuilder.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        stream_factory: StreamFactory.new,
        input_contract: Contracts::VerificationObligationValidityScanStart.new,
        event_plan_contract: Contracts::VerificationObligationValidityScanStartEventPlan.new
      )
        @event_store = event_store
        @exact_loader = exact_loader
        @loader = loader
        @decider = decider
        @retry_policy = retry_policy
        @identity_builder = identity_builder
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @stream_factory = stream_factory
        @input_contract = input_contract
        @event_plan_contract = event_plan_contract
      end

      def call(invocation)
        source = @exact_loader.call(invocation.source_reference)
        verify_input!(invocation, source)
        preparation = VerificationObligationValidityScans::StartPreparationV1.new(
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
        snapshot = @loader.call(command.scan_id)
        decision = @decider.call(state: snapshot.state, command:, started_at: preparation.started_at)
        return decision if decision.failure?

        plan = decision.value!
        stream = @stream_factory.verification_obligation_validity_scan(command.scan_id)
        verify_event_plan!(plan, command:, expected_stream: stream, started_at: preparation.started_at)
        physical = @event_factory.build!(
          event: plan.events.sole,
          event_id: preparation.event_id,
          metadata: metadata(command),
          markers: markers(command),
          caused_by: invocation.source_event
        )
        expected_revision = snapshot.latest_revision || :no_stream
        Success(@event_store.append(stream, [ physical ], expected_revision:).sole)
      end

      def verify_input!(invocation, source)
        command = invocation.command
        expected_identity = @identity_builder.scan(
          superseding_partition_event: command.superseding_partition_event,
          rule_version: command.rule_version
        )
        result = @input_contract.call(invocation:, source:, expected_identity:)
        return if result.success?

        raise ArgumentError, "validity scan start violates its dry-rb contract: #{result.errors.to_h.inspect}"
      end

      def verify_event_plan!(plan, command:, expected_stream:, started_at:)
        result = @event_plan_contract.call(plan:, command:, expected_stream:, started_at:)
        return if result.success?

        raise ArgumentError, "validity scan start plan violates its dry-rb contract: #{result.errors.to_h.inspect}"
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
          "verification-obligation-validity-scan:#{command.scan_id}",
          "change-set:#{command.change_set_id}",
          "command:#{command.command_id}"
        ].freeze
      end
    end
  end
end
