# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteClaimVerificationObligation < Dry::Operation
      TOOL_NAME = "verification_obligation_claim"

      def initialize(
        event_store:,
        preparer: PrepareClaimVerificationObligation.new,
        decider: Domain::VerificationObligationClaims::Claim.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandResultBuilder.new,
        definition_loader: VerificationObligations::DefinitionLoader.new(event_store:),
        history_contract: Contracts::VerificationObligationClaimHistory.new,
        event_plan_contract: Contracts::VerificationObligationClaimEventPlan.new
      )
        @event_store = event_store
        @preparer = preparer
        @decider = decider
        @input_digest = input_digest
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @completion_builder = completion_builder
        @definition_loader = definition_loader
        @history_contract = history_contract
        @event_plan_contract = event_plan_contract
      end

      def call(input)
        command = step @preparer.call(input)
        step call_command(command)
      end

      def call_command(command, caused_by: nil)
        preparation = prepare_logical_values(command)
        execute_attempt(command:, preparation:, caused_by:)
      rescue PgEventstore::WrongExpectedRevisionError
        Failure(
          OutcomeError.new(
            code: :stale_stream,
            message: "Verification obligation changed concurrently; the request may succeed if retried",
            details: { obligation_id: command.obligation_id }
          )
        )
      end

      private

      def prepare_logical_values(command)
        VerificationObligationClaimPreparationV1.new(
          claim_id: @id_generator.uuid_v7,
          claimed_at: @clock.now,
          input_digest: @input_digest.verification_obligation_claim(command),
          claim_event_id: @id_generator.uuid_v7,
          correlation_id: @id_generator.uuid_v7
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        state, latest_revision = load_state(command.obligation_id)
        decision = @decider.call(
          state:,
          command:,
          claim_id: preparation.claim_id,
          claimed_at: preparation.claimed_at
        )
        return decision if decision.failure?

        plan = decision.value!
        verify_event_plan!(plan, state:, command:, preparation:)
        persisted_events = persist_domain_plan(
          plan,
          state:,
          command:,
          event_id: preparation.claim_event_id,
          caused_by:,
          correlation_id: caused_by ? nil : preparation.correlation_id,
          expected_revision: latest_revision
        )
        claim = plan.events.sole
        completion = @completion_builder.verification_obligation_claim(
          command:,
          claim:,
          input_digest: preparation.input_digest,
          persisted_events:,
          completed_at: preparation.claimed_at
        )

        Success(completion)
      end

      def load_state(obligation_id)
        definition = @definition_loader.call(obligation_id)
        events = @event_store.read_grouped(
          @stream_factory.verification_obligation(obligation_id),
          EventQueries::VERIFICATION_OBLIGATION_FOR_CLAIM
        ).to_h { |event| [ event.type, event ] }
        claim_event = events["VerificationObligationClaimed"]
        terminal_event = latest_terminal_event(events)
        state = Domain::VerificationObligationClaims::State.new(
          obligation: definition&.definition,
          obligation_event: definition&.reference,
          claim: claim_event ? load_event(claim_event) : nil,
          terminal_status: terminal_event && terminal_status(terminal_event),
          terminal_event: terminal_event && event_reference(terminal_event)
        )
        validation = @history_contract.call(state:, obligation_id:)
        return [ state, events.values.map(&:stream_revision).max || -1 ] if validation.success?

        raise InvalidVerificationObligationClaimHistory, validation.errors.to_h.inspect
      end

      def latest_terminal_event(events)
        %w[
          VerificationObligationSatisfied
          VerificationObligationFailed
          VerificationObligationWaived
          VerificationObligationInvalidated
        ].filter_map { events[_1] }.max_by(&:stream_revision)
      end

      def terminal_status(event)
        event.type.delete_prefix("VerificationObligation").downcase
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def verify_event_plan!(plan, state:, command:, preparation:)
        validation = @event_plan_contract.call(
          plan:,
          state:,
          command:,
          claim_id: preparation.claim_id,
          claimed_at: preparation.claimed_at
        )
        return if validation.success?

        raise InvalidVerificationObligationClaimEventPlan, validation.errors.to_h.inspect
      end

      def persist_domain_plan(plan, state:, command:, event_id:, caused_by:, correlation_id:, expected_revision:)
        claim = plan.events.sole
        event = @event_factory.build!(
          event: claim,
          event_id:,
          metadata: command_metadata(command),
          markers: claim_markers(state, command, claim),
          caused_by:,
          correlation_id:
        )

        @event_store.append(plan.writes.sole.stream, [ event ], expected_revision:)
      end

      def claim_markers(state, command, claim)
        (state.scope_markers + [
          "claim:#{claim.claim_id}",
          "claimant:#{claim.claimant_id}",
          "command:#{command.command_id}"
        ]).freeze
      end

      def command_metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: "verification-obligation-claim/v1"
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
