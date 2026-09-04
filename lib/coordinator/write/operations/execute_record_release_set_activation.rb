# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteRecordReleaseSetActivation < Dry::Operation
      TOOL_NAME = "release_activation_record"

      def initialize(
        event_store:,
        preparer: PrepareRecordReleaseSetActivation.new,
        history_loader: ReleaseSets::HistoryLoader.new(event_store:),
        decider: Domain::ReleaseSets::RecordActivation.new,
        digest_builder: ReleaseSets::ActivationDigestBuilder.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandResultBuilder.new,
        event_plan_contract: Contracts::ReleaseSetActivationEventPlan.new
      )
        @event_store = event_store
        @preparer = preparer
        @history_loader = history_loader
        @decider = decider
        @digest_builder = digest_builder
        @input_digest = input_digest
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @stream_factory = stream_factory
        @completion_builder = completion_builder
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
        ReleaseSetLifecyclePreparationV1.new(
          occurred_at: @clock.now,
          input_digest: @input_digest.release_activation_record(command),
          domain_event_id: @id_generator.uuid_v7
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        state = @history_loader.call(command.release_set_id)
        decision = @decider.call(state:, command:)
        return decision if decision.failure?

        plan = decision.value!
        verify_event_plan!(plan, state:, command:)
        activation = plan.events.sole
        activation_digest = @digest_builder.call(
          release_set_id: command.release_set_id,
          release_digest: state.preparation.payload.release_digest,
          verification_event: command.verification_event,
          verification_digest: command.verification_digest,
          activation_point: command.activation_point,
          policy_version: command.policy_version
        )
        persisted = persist_domain(
          activation,
          state:,
          command:,
          preparation:,
          activation_digest:,
          caused_by:
        )
        completion = @completion_builder.release_activation_record(
          command:,
          activation:,
          activation_digest:,
          activation_event: persisted,
          input_digest: preparation.input_digest,
          persisted_events: [ persisted ],
          completed_at: preparation.occurred_at
        )
        Success(completion)
      end

      def verify_event_plan!(plan, state:, command:)
        result = @event_plan_contract.call(plan:, state:, command:)
        raise InvalidReleaseSetActivationEventPlan, result.errors.to_h.inspect if result.failure?
      end

      def persist_domain(activation, state:, command:, preparation:, activation_digest:, caused_by:)
        physical = @event_factory.build!(
          event: activation,
          event_id: preparation.domain_event_id,
          metadata: Metadata::ReleaseSetActivationV2.new(
            command_id: command.command_id,
            actor_kind: command.actor.kind,
            actor_id: command.actor.id,
            recorded_by: "coordinator",
            policy_version: command.policy_version,
            activation_digest:,
            release_digest: state.preparation.payload.release_digest,
            verification_digest: command.verification_digest
          ),
          markers: [
            "release-set:#{command.release_set_id}",
            "release-activation-kind:#{activation.activation_point.kind}",
            "release-verification-event:#{command.verification_event.event_id}",
            "command:#{command.command_id}"
          ],
          caused_by:,
          correlation_id: state.preparation.correlation_id
        )
        @event_store.append(@stream_factory.release_set(command.release_set_id), [ physical ]).sole
      end
    end
  end
end
