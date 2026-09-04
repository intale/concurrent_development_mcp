# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteWaiveVerificationObligation < Dry::Operation
      TOOL_NAME = "verification_obligation_waive"

      def initialize(
        event_store:,
        preparer: PrepareWaiveVerificationObligation.new,
        decider: Domain::VerificationObligationWaivers::Waive.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandResultBuilder.new,
        definition_loader: VerificationObligations::DefinitionLoader.new(event_store:),
        history_contract: Contracts::VerificationObligationWaiverHistory.new,
        event_plan_contract: Contracts::VerificationObligationWaiverEventPlan.new
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
        VerificationObligationWaiverPreparationV1.new(
          waived_at: @clock.now,
          input_digest: @input_digest.verification_obligation_waive(command),
          waiver_event_id: @id_generator.uuid_v7,
          correlation_id: @id_generator.uuid_v7
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        state, latest_revision = load_state(command.obligation_id)
        decision = @decider.call(state:, command:)
        return decision if decision.failure?

        plan = decision.value!
        verify_event_plan!(plan, state:, command:, preparation:)
        persisted = persist_waiver(
          plan.events.sole,
          obligation: state.obligation,
          command:,
          preparation:,
          caused_by:,
          expected_revision: latest_revision
        )
        completion = @completion_builder.verification_obligation_waive(
          command:,
          waiver: plan.events.sole,
          input_digest: preparation.input_digest,
          persisted_events: [ persisted ],
          completed_at: preparation.waived_at
        )
        Success(completion)
      end

      def load_state(obligation_id)
        definition = @definition_loader.call(obligation_id)
        grouped = @event_store.read_grouped(
          @stream_factory.verification_obligation(obligation_id),
          EventQueries::VERIFICATION_OBLIGATION_LIFECYCLE
        ).to_h { [ _1.type, _1 ] }
        obligation = definition&.definition
        state = Domain::VerificationObligationWaivers::State.new(
          obligation:,
          obligation_event: definition&.reference,
          satisfied: payload_or_nil(grouped["VerificationObligationSatisfied"]),
          satisfied_event: reference_or_nil(grouped["VerificationObligationSatisfied"]),
          failed: payload_or_nil(grouped["VerificationObligationFailed"]),
          failed_event: reference_or_nil(grouped["VerificationObligationFailed"]),
          waived: payload_or_nil(grouped["VerificationObligationWaived"]),
          waived_event: reference_or_nil(grouped["VerificationObligationWaived"]),
          invalidated: payload_or_nil(grouped["VerificationObligationInvalidated"]),
          invalidated_event: reference_or_nil(grouped["VerificationObligationInvalidated"])
        )
        verify_history!(state, obligation_id:)
        latest_revision = [ definition&.event, *grouped.values ].compact.map(&:stream_revision).max || -1
        [ state, latest_revision ]
      end

      def verify_history!(state, obligation_id:)
        validation = @history_contract.call(state:, obligation_id:)
        return if validation.success?

        raise InvalidVerificationObligationWaiverHistory, validation.errors.to_h.inspect
      end

      def verify_event_plan!(plan, state:, command:, preparation:)
        validation = @event_plan_contract.call(
          plan:,
          state:,
          command:
        )
        return if validation.success?

        raise InvalidVerificationObligationWaiverEventPlan, validation.errors.to_h.inspect
      end

      def persist_waiver(waiver, obligation:, command:, preparation:, caused_by:, expected_revision:)
        physical = @event_factory.build!(
          event: waiver,
          event_id: preparation.waiver_event_id,
          metadata: command_metadata(command, obligation, preparation),
          markers: scope_markers(obligation) + [
            "verification-obligation-status:waived",
            "command:#{command.command_id}"
          ],
          caused_by:,
          correlation_id: root_correlation_id(preparation, caused_by)
        )
        @event_store.append(
          @stream_factory.verification_obligation(command.obligation_id),
          [ physical ],
          expected_revision:
        ).sole
      end

      def scope_markers(obligation)
        source = obligation.source_candidate
        target = obligation.target_candidate
        [
          "verification-obligation:#{obligation.obligation_id}",
          "verification-obligation-kind:#{obligation.kind}",
          "change-set:#{obligation.change_set_id}",
          "source-candidate:#{source.candidate_id}",
          "target-candidate:#{target.candidate_id}",
          "candidate:#{source.candidate_id}",
          "candidate:#{target.candidate_id}",
          "work-item:#{source.work_item_id}",
          "work-item:#{target.work_item_id}",
          "repository:#{source.repository_id}",
          "repository:#{target.repository_id}",
          "enforcement:#{obligation.enforcement}",
          "decision:#{obligation.policy.head.decision_id}"
        ]
      end

      def root_correlation_id(preparation, caused_by)
        preparation.correlation_id unless caused_by
      end

      def command_metadata(command, obligation, preparation)
        Metadata::VerificationWaiverV2.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: "verification-obligation-waiver/v2",
          policy: obligation.policy,
          waiver_input_digest: preparation.input_digest
        )
      end

      def payload_or_nil(event)
        event && load_event(event)
      end

      def reference_or_nil(event)
        event && event_reference(event)
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
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
