# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteCompleteActivatedReleaseSet < Dry::Operation
      TOOL_NAME = "release_activated_complete_policy"

      def initialize(
        event_store:,
        history_loader: ReleaseSets::HistoryLoader.new(event_store:),
        decider: Domain::ReleaseSets::CompleteActivated.new,
        digest_builder: ReleaseSets::CompletionDigestBuilder.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        completion_builder: CommandResultBuilder.new,
        event_plan_contract: Contracts::ReleaseSetActivatedCompletionEventPlan.new
      )
        @event_store = event_store
        @history_loader = history_loader
        @decider = decider
        @digest_builder = digest_builder
        @input_digest = input_digest
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @completion_builder = completion_builder
        @event_plan_contract = event_plan_contract
      end

      def call_command(command, caused_by:)
        steps do
          preparation = prepare_logical_values(command)
          step @event_store.multiple { execute_attempt(command:, preparation:, caused_by:) }
        end
      end

      private

      def prepare_logical_values(command)
        ReleaseSetMultiEventPreparationV1.new(
          occurred_at: @clock.now,
          input_digest: @input_digest.release_activated_complete(command),
          event_ids: 2.times.map { @id_generator.uuid_v7 }
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        state = @history_loader.call(command.release_set_id)
        decision = @decider.call(state:, command:)
        return decision if decision.failure?

        plan = decision.value!
        verify_event_plan!(plan, state:, command:)
        completion_digest = completion_digest(state:, command:)
        persisted = persist_plan(plan, state:, command:, preparation:, completion_digest:, caused_by:)
        completion = @completion_builder.release_activated_complete(
          command:,
          change_set_id: state.preparation.payload.change_set_id,
          outcome: "activated",
          source_event: command.activation_event,
          completion_digest:,
          completion_event: persisted.last,
          input_digest: preparation.input_digest,
          persisted_events: persisted,
          completed_at: preparation.occurred_at
        )
        Success(completion)
      end

      def completion_digest(state:, command:)
        @digest_builder.call(
          release_set_id: command.release_set_id,
          release_digest: state.preparation.payload.release_digest,
          outcome: "activated",
          source_event: command.activation_event,
          compensation_evidence: [],
          rule_version: command.rule_version
        )
      end

      def verify_event_plan!(plan, state:, command:)
        result = @event_plan_contract.call(plan:, state:, command:)
        raise InvalidReleaseSetActivatedCompletionEventPlan, result.errors.to_h.inspect if result.failure?
      end

      def persist_plan(plan, state:, command:, preparation:, completion_digest:, caused_by:)
        parent = caused_by
        plan.writes.zip(preparation.event_ids).map do |write, event_id|
          physical = @event_factory.build!(
            event: write.event,
            event_id:,
            metadata: event_metadata(write.event, state:, command:, completion_digest:),
            markers: [ "release-set:#{command.release_set_id}", "release-completion:activated", "command:#{command.command_id}" ],
            caused_by: parent,
            correlation_id: state.preparation.correlation_id
          )
          persisted = @event_store.append(write.stream, [ physical ]).sole
          parent = persisted
          persisted
        end
      end

      def event_metadata(event, state:, command:, completion_digest:)
        attributes = {
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: command.rule_version
        }
        return EventMetadata.new(**attributes) unless event.is_a?(Events::ReleaseSetOutcomeRecordedV1)

        Metadata::ReleaseSetOutcomeV1.new(
          **attributes,
          completion_digest:,
          release_digest: state.preparation.payload.release_digest,
          rule_version: command.rule_version
        )
      end
    end
  end
end
