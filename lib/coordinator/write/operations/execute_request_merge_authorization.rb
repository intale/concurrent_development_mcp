# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteRequestMergeAuthorization < Dry::Operation
      TOOL_NAME = "merge_authorization_request"

      def initialize(
        event_store:,
        preparer: PrepareRequestMergeAuthorization.new,
        evaluator: MergeAuthorizations::Evaluator.new(event_store:),
        decider: Domain::MergeAuthorizations::Decide.new,
        input_digest: CommandInputDigest.new,
        decision_digest_builder: MergeAuthorizations::DecisionDigestBuilder.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandResultBuilder.new,
        evaluation_contract: Contracts::MergeAuthorizationEvaluation.new,
        event_plan_contract: Contracts::MergeAuthorizationEventPlan.new
      )
        @event_store = event_store
        @preparer = preparer
        @evaluator = evaluator
        @decider = decider
        @input_digest = input_digest
        @decision_digest_builder = decision_digest_builder
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @completion_builder = completion_builder
        @evaluation_contract = evaluation_contract
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
        MergeAuthorizationPreparationV1.new(
          authorization_id: @id_generator.uuid_v7,
          decided_at: @clock.now,
          input_digest: @input_digest.merge_authorization_request(command),
          decision_event_id: @id_generator.uuid_v7,
          correlation_id: @id_generator.uuid_v7
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        evaluation = @evaluator.call(command, decided_at: preparation.decided_at)
        verify_evaluation!(evaluation, command:)
        outcome = evaluation.granted? ? "granted" : "denied"
        decision_digest = @decision_digest_builder.call(
          policy_version: command.policy_version,
          input_digest: preparation.input_digest,
          snapshot_binding: command.snapshot_binding,
          expected_impact_policy: command.expected_impact_policy,
          evaluation:,
          outcome:
        )
        plan = @decider.call(
          command:,
          evaluation:,
          authorization_id: preparation.authorization_id
        ).value!
        verify_event_plan!(plan, command:, evaluation:, preparation:)
        decision = plan.events.sole
        persisted = persist_decision(
          decision,
          command:,
          preparation:,
          decision_digest:,
          caused_by:
        )
        completion = @completion_builder.merge_authorization_request(
          command:,
          decision:,
          decision_digest:,
          input_digest: preparation.input_digest,
          persisted_events: [ persisted ],
          completed_at: preparation.decided_at,
          decided_at: persisted.created_at.utc.iso8601(6)
        )
        Success(completion)
      end

      def verify_evaluation!(evaluation, command:)
        result = @evaluation_contract.call(evaluation:, command:)
        return if result.success?

        raise InvalidMergeAuthorizationEvaluation, result.errors.to_h.inspect
      end

      def verify_event_plan!(plan, command:, evaluation:, preparation:)
        result = @event_plan_contract.call(
          plan:,
          command:,
          evaluation:,
          authorization_id: preparation.authorization_id
        )
        return if result.success?

        raise InvalidMergeAuthorizationEventPlan, result.errors.to_h.inspect
      end

      def persist_decision(decision, command:, preparation:, decision_digest:, caused_by:)
        physical = @event_factory.build!(
          event: decision,
          event_id: preparation.decision_event_id,
          metadata: command_metadata(command, preparation, decision_digest),
          markers: event_markers(command, decision),
          caused_by:,
          correlation_id: root_correlation_id(preparation, caused_by)
        )
        @event_store.append(
          @stream_factory.merge_authorization(preparation.authorization_id),
          [ physical ]
        ).sole
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def event_markers(command, decision)
        outcome = decision.is_a?(Events::MergeAuthorizationGrantedV2) ? "granted" : "denied"
        markers = [
          "merge-authorization:#{decision.authorization_id}",
          "merge-authorization-outcome:#{outcome}",
          "merge-authorization-policy:#{command.policy_version}",
          "merge-snapshot:#{command.merge_snapshot_id}",
          "repository:#{command.target_base_observation.repository_id}",
          "target-branch:#{command.target_base_observation.target_branch}",
          "command:#{command.command_id}"
        ]
        policy = decision.evaluation.current_policy
        markers << "decision-partition:#{policy.partition.partition_id}" if policy
        markers.freeze
      end

      def root_correlation_id(preparation, caused_by)
        preparation.correlation_id unless caused_by
      end

      def command_metadata(command, preparation, decision_digest)
        Metadata::MergeAuthorizationV2.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: command.policy_version,
          decision_digest:,
          expected_impact_policy: command.expected_impact_policy,
          input_digest: preparation.input_digest
        )
      end
    end
  end
end
