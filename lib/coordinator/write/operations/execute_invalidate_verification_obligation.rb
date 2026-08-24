# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteInvalidateVerificationObligation
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        exact_loader: CandidateObligations::ExactEventLoader.new(event_store:),
        decider: Domain::VerificationObligationInvalidations::Invalidate.new,
        identity_builder: VerificationObligationInvalidations::IdentityBuilder.new,
        digest_builder: VerificationObligationInvalidations::DigestBuilder.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        invocation_contract: Contracts::VerificationObligationInvalidationInvocation.new,
        evidence_contract: Contracts::VerificationObligationInvalidationEvidence.new,
        history_contract: Contracts::VerificationObligationInvalidationHistory.new,
        event_plan_contract: Contracts::VerificationObligationInvalidationEventPlan.new
      )
        @event_store = event_store
        @exact_loader = exact_loader
        @decider = decider
        @identity_builder = identity_builder
        @digest_builder = digest_builder
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @invocation_contract = invocation_contract
        @evidence_contract = evidence_contract
        @history_contract = history_contract
        @event_plan_contract = event_plan_contract
      end

      def call(invocation)
        verify_invocation!(invocation)
        preparation = VerificationObligationInvalidations::PreparationV1.new(
          invalidated_at: @clock.now,
          event_id: @id_generator.uuid_v7
        )
        @event_store.multiple { execute_attempt(invocation:, preparation:) }
      end

      private

      def execute_attempt(invocation:, preparation:)
        command = invocation.command
        obligation = @exact_loader.call(command.obligation_event)
        superseding = @exact_loader.call(command.superseding_partition_event)
        verify_evidence!(command, obligation, superseding)
        state = load_state(command.obligation_id)
        decision = @decider.call(
          state:,
          command:,
          superseding_partition: superseding,
          invalidated_at: preparation.invalidated_at
        )
        return decision if decision.failure?

        plan = decision.value!
        digest = invalidation_digest(state, command)
        verify_event_plan!(plan, state, command, digest, preparation.invalidated_at)
        physical = @event_factory.build!(
          event: plan.events.sole,
          event_id: preparation.event_id,
          metadata: metadata(command),
          markers: scope_markers(state.obligation, command),
          caused_by: invocation.caused_by_event
        )
        Success(
          @event_store.append(
            @stream_factory.verification_obligation(command.obligation_id),
            [ physical ]
          ).sole
        )
      end

      def load_state(obligation_id)
        grouped = @event_store.read_grouped(
          @stream_factory.verification_obligation(obligation_id),
          EventQueries::VERIFICATION_OBLIGATION_LIFECYCLE
        ).to_h { [ _1.type, _1 ] }
        state = Domain::VerificationObligationInvalidations::State.new(
          obligation: payload(grouped["VerificationObligationCreated"]),
          obligation_event: reference(grouped["VerificationObligationCreated"]),
          satisfied: payload(grouped["VerificationObligationSatisfied"]),
          satisfied_event: reference(grouped["VerificationObligationSatisfied"]),
          failed: payload(grouped["VerificationObligationFailed"]),
          failed_event: reference(grouped["VerificationObligationFailed"]),
          waived: payload(grouped["VerificationObligationWaived"]),
          waived_event: reference(grouped["VerificationObligationWaived"]),
          invalidated: payload(grouped["VerificationObligationInvalidated"]),
          invalidated_event: reference(grouped["VerificationObligationInvalidated"])
        )
        result = @history_contract.call(state:, obligation_id:)
        raise InvalidVerificationObligationInvalidationHistory, result.errors.to_h.inspect if result.failure?

        state
      end

      def verify_invocation!(invocation)
        command = invocation.command
        identity = @identity_builder.call(
          obligation_event: command.obligation_event,
          superseding_partition_event: command.superseding_partition_event,
          rule_version: command.rule_version
        )
        result = @invocation_contract.call(invocation:, expected_identity: identity)
        return if result.success?

        raise ArgumentError, "invalidation invocation violates its dry-rb contract: #{result.errors.to_h.inspect}"
      end

      def verify_evidence!(command, obligation, superseding)
        result = @evidence_contract.call(command:, obligation:, superseding_partition: superseding)
        return if result.success?

        raise ArgumentError, "invalidation evidence violates its dry-rb contract: #{result.errors.to_h.inspect}"
      end

      def verify_event_plan!(plan, state, command, digest, invalidated_at)
        result = @event_plan_contract.call(
          plan:,
          state:,
          command:,
          invalidation_digest: digest,
          invalidated_at:
        )
        return if result.success?

        raise InvalidVerificationObligationInvalidationEventPlan, result.errors.to_h.inspect
      end

      def invalidation_digest(state, command)
        @digest_builder.call(
          obligation_event: state.obligation_event,
          invalidated_policy: state.obligation.policy,
          superseding_partition_event: command.superseding_partition_event,
          previous_status: state.status,
          previous_terminal_event: state.previous_terminal_event,
          rule_version: command.rule_version
        )
      end

      def payload(event)
        return unless event

        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def reference(event)
        return unless event

        EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
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

      def scope_markers(obligation, command)
        source = obligation.source_candidate
        target = obligation.target_candidate
        [
          "verification-obligation:#{obligation.obligation_id}",
          "verification-obligation-kind:#{obligation.kind}",
          "verification-obligation-status:invalidated",
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
          "decision:#{obligation.policy.head.decision_id}",
          "command:#{command.command_id}"
        ].freeze
      end
    end
  end
end
