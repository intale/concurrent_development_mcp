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
        completion_builder: CommandCompletionBuilder.new,
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
        VerificationObligationClaimPreparationV1.new(
          claim_id: @id_generator.uuid_v7,
          claimed_at: @clock.now,
          input_digest: @input_digest.verification_obligation_claim(command),
          claim_event_id: @id_generator.uuid_v7,
          completion_event_id: @id_generator.uuid_v7
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        replay = replay_result(command:, input_digest: preparation.input_digest)
        return replay if replay

        state = load_state(command.obligation_id)
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
          caused_by:
        )
        claim = plan.events.sole
        completion = @completion_builder.verification_obligation_claim(
          command:,
          claim:,
          input_digest: preparation.input_digest,
          persisted_events:,
          completed_at: preparation.claimed_at
        )
        persist_completion(
          completion,
          command:,
          event_id: preparation.completion_event_id,
          caused_by:
        )

        Success(completion)
      end

      def replay_result(command:, input_digest:)
        completion = load_completion(command.command_id)
        return unless completion

        if completion.tool_name == TOOL_NAME && completion.canonical_input_digest == input_digest
          Success(completion)
        else
          Failure(
            OutcomeError.new(
              code: :command_id_reused,
              message: "Command ID is already bound to another tool or input",
              details: {
                command_id: command.command_id,
                existing_tool_name: completion.tool_name,
                existing_input_digest: completion.canonical_input_digest,
                requested_tool_name: TOOL_NAME,
                requested_input_digest: input_digest
              }
            )
          )
        end
      end

      def load_completion(command_id)
        event = @event_store.read(
          @stream_factory.command(command_id),
          EventQueries::COMMAND_COMPLETION
        ).first
        return unless event

        load_event(event)
      end

      def load_state(obligation_id)
        events = @event_store.read_grouped(
          @stream_factory.verification_obligation(obligation_id),
          EventQueries::VERIFICATION_OBLIGATION_FOR_CLAIM
        ).to_h { |event| [ event.type, event ] }
        creation_event = events["VerificationObligationCreated"]
        claim_event = events["VerificationObligationClaimed"]
        state = Domain::VerificationObligationClaims::State.new(
          obligation: creation_event ? load_event(creation_event) : nil,
          obligation_event: creation_event ? event_reference(creation_event) : nil,
          claim: claim_event ? load_event(claim_event) : nil
        )
        validation = @history_contract.call(state:, obligation_id:)
        return state if validation.success?

        raise InvalidVerificationObligationClaimHistory, validation.errors.to_h.inspect
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

      def persist_domain_plan(plan, state:, command:, event_id:, caused_by:)
        claim = plan.events.sole
        event = @event_factory.build!(
          event: claim,
          event_id:,
          metadata: command_metadata(command),
          markers: claim_markers(state, command, claim),
          caused_by:
        )

        @event_store.append(plan.writes.sole.stream, [ event ])
      end

      def persist_completion(completion, command:, event_id:, caused_by:)
        event = @event_factory.build!(
          event: completion,
          event_id:,
          metadata: command_metadata(command),
          markers: [ "command:#{command.command_id}" ],
          caused_by:
        )

        @event_store.append(@stream_factory.command(command.command_id), [ event ])
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
