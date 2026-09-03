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
        policy_loader: CandidateObligations::ImpactPolicyLoader.new(event_store:),
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
        @policy_loader = policy_loader
        @history_contract = history_contract
        @event_plan_contract = event_plan_contract
      end

      def call(input)
        command = step @preparer.call(input)
        step call_command(command)
      end

      def call_command(command, caused_by: nil)
        steps do
          preparation = prepare_logical_values(command)
          step @event_store.multiple { execute_attempt(command:, preparation:, caused_by:) }
        end
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
        state = load_state(command.obligation_id, preparation.waived_at)
        decision = @decider.call(
          state:,
          command:,
          waiver_input_digest: preparation.input_digest,
          waived_at: preparation.waived_at
        )
        return decision if decision.failure?

        plan = decision.value!
        verify_event_plan!(plan, state:, command:, preparation:)
        persisted = persist_waiver(
          plan.events.sole,
          obligation: state.obligation,
          command:,
          preparation:,
          caused_by:
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

      def load_state(obligation_id, observed_at)
        grouped = @event_store.read_grouped(
          @stream_factory.verification_obligation(obligation_id),
          EventQueries::VERIFICATION_OBLIGATION_LIFECYCLE
        ).to_h { [ _1.type, _1 ] }
        creation = grouped["VerificationObligationCreated"]
        obligation = creation && load_event(creation)
        state = Domain::VerificationObligationWaivers::State.new(
          obligation:,
          obligation_event: reference_or_nil(creation),
          satisfied: payload_or_nil(grouped["VerificationObligationSatisfied"]),
          satisfied_event: reference_or_nil(grouped["VerificationObligationSatisfied"]),
          failed: payload_or_nil(grouped["VerificationObligationFailed"]),
          failed_event: reference_or_nil(grouped["VerificationObligationFailed"]),
          waived: payload_or_nil(grouped["VerificationObligationWaived"]),
          waived_event: reference_or_nil(grouped["VerificationObligationWaived"]),
          invalidated: payload_or_nil(grouped["VerificationObligationInvalidated"]),
          invalidated_event: reference_or_nil(grouped["VerificationObligationInvalidated"]),
          policy_current: current_policy?(obligation, observed_at)
        )
        verify_history!(state, obligation_id:)
        state
      end

      def current_policy?(obligation, observed_at)
        return false unless obligation

        observation = @policy_loader.call(
          policy_partition_event: obligation.policy.partition_event,
          policy_head: obligation.policy.head,
          change_set_id: obligation.change_set_id,
          observed_at:
        )
        observation.status == "gating" && observation.evidence == obligation.policy
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
          command:,
          waiver_input_digest: preparation.input_digest,
          waived_at: preparation.waived_at
        )
        return if validation.success?

        raise InvalidVerificationObligationWaiverEventPlan, validation.errors.to_h.inspect
      end

      def persist_waiver(waiver, obligation:, command:, preparation:, caused_by:)
        physical = @event_factory.build!(
          event: waiver,
          event_id: preparation.waiver_event_id,
          metadata: command_metadata(command),
          markers: scope_markers(obligation) + [
            "verification-obligation-status:waived",
            "command:#{command.command_id}"
          ],
          caused_by:,
          correlation_id: root_correlation_id(preparation, caused_by)
        )
        @event_store.append(
          @stream_factory.verification_obligation(command.obligation_id),
          [ physical ]
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

      def command_metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: "verification-obligation-waiver/v1"
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
