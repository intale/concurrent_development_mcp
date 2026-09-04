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
        snapshot = @loader.call(command.scan_id)
        decision = @decider.call(state: snapshot.state, command:)
        return decision if decision.failure?

        plan = decision.value!
        stream = @stream_factory.verification_obligation_validity_scan(command.scan_id)
        verify_event_plan!(plan, command:, expected_stream: stream)
        physical = physical_events(plan.events, command:, preparation:, caused_by: invocation.caused_by)
        Success(@event_store.append(stream, physical).first)
      end

      def verify_input!(invocation, source)
        result = @input_contract.call(invocation:, source:)
        return if result.success?

        raise ArgumentError, "validity scan start violates its dry-rb contract: #{result.errors.to_h.inspect}"
      end

      def verify_event_plan!(plan, command:, expected_stream:)
        result = @event_plan_contract.call(plan:, command:, expected_stream:)
        return if result.success?

        raise ArgumentError, "validity scan start plan violates its dry-rb contract: #{result.errors.to_h.inspect}"
      end

      def physical_events(events, command:, preparation:, caused_by:)
        parent = caused_by
        events.zip(preparation.event_ids).map do |event, event_id|
          physical = @event_factory.build!(
            event:,
            event_id:,
            metadata: metadata(event, command),
            markers: markers(command, event),
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
          policy_version: event.is_a?(Events::VerificationObligationValidityScanSourceLinkedV1) ? nil : command.rule_version
        )
      end

      def markers(command, event)
        values = [
          "verification-obligation-validity-scan:#{command.scan_id}",
          "change-set:#{command.change_set_id}",
          "superseding-partition-event:#{command.superseding_partition_event.event_id}",
          "command:#{command.command_id}"
        ]
        values << "source-role:#{event.role}" if event.is_a?(Events::VerificationObligationValidityScanSourceLinkedV1)
        values.freeze
      end
    end
  end
end
