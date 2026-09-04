# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteRecordMergeObservation < Dry::Operation
      TOOL_NAME = "merge_observation_record"

      def initialize(
        event_store:,
        preparer: PrepareRecordMergeObservation.new,
        evaluator: MergeAuthorizations::Evaluator.new(event_store:),
        decider: Domain::MergeObservations::Record.new,
        input_digest: CommandInputDigest.new,
        observation_digest_builder: MergeObservations::ObservationDigestBuilder.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandResultBuilder.new,
        event_plan_contract: Contracts::MergeObservationEventPlan.new
      )
        @event_store = event_store
        @preparer = preparer
        @evaluator = evaluator
        @decider = decider
        @input_digest = input_digest
        @observation_digest_builder = observation_digest_builder
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
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
        MergeObservationPreparationV1.new(
          recorded_at: @clock.now,
          input_digest: @input_digest.merge_observation_record(command),
          observation_event_id: @id_generator.uuid_v7,
          authorization_link_event_id: @id_generator.uuid_v7,
          correlation_id: @id_generator.uuid_v7
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        history = load_history(command, recorded_at: preparation.recorded_at)
        observation_digest = if history.authorization
                               @observation_digest_builder.call(
                                 command:,
                                 authorization: history.authorization.decision
                               )
        else
                               preparation.input_digest
        end
        decision = @decider.call(
          history:,
          command:
        )
        return decision if decision.failure?

        plan = decision.value!
        verify_event_plan!(
          plan,
          history:,
          command:
        )
        persisted = persist_plan(
          plan,
          command:,
          preparation:,
          observation_digest:,
          caused_by:
        )
        completion = @completion_builder.merge_observation_record(
          command:,
          observation: plan.events.fetch(0),
          observation_digest:,
          input_digest: preparation.input_digest,
          persisted_events: persisted,
          completed_at: preparation.recorded_at,
          recorded_at: persisted.fetch(0).created_at.utc.iso8601(6)
        )
        Success(completion)
      end

      def load_history(command, recorded_at:)
        authorization, authorization_event = load_authorization(command.authorization_event)
        evaluation = authorization && reevaluate(authorization, command, recorded_at:)
        existing = @event_store.read(
          @stream_factory.merge_snapshot(command.merge_snapshot_id),
          EventQueries::MERGE_OBSERVATION
        ).first
        Domain::MergeObservations::HistoryV1.new(
          authorization:,
          current_evaluation: evaluation,
          existing_observation: existing && load_event(existing),
          existing_observation_event: existing && event_reference(existing)
        )
      end

      def load_authorization(reference)
        stream = @stream_factory.merge_authorization(reference.stream_id)
        physical = @event_store.read_at(stream, reference.stream_revision)
        return [ nil, nil ] unless physical && event_reference(physical) == reference
        return [ nil, nil ] unless physical.type == "MergeAuthorizationGranted"

        decision = load_event(physical)
        [
          MergeAuthorizations::DecisionEvidenceV2.new(
            decision:,
            event: event_reference(physical),
            decision_digest: physical.metadata.fetch("decision_digest"),
            expected_impact_policy: metadata_expected_policy(physical.metadata),
            policy_version: physical.metadata.fetch("policy_version")
          ),
          event_reference(physical)
        ]
      end

      def reevaluate(authorization_evidence, command, recorded_at:)
        authorization = authorization_evidence.decision
        authorization_command = Commands::RequestMergeAuthorization.new(
          command_id: command.command_id,
          actor: command.actor,
          merge_snapshot_id: authorization.merge_snapshot_id,
          snapshot_binding: authorization.snapshot_binding,
          target_base_observation: authorization.evaluation.target_base_observation,
          expected_impact_policy: authorization_evidence.expected_impact_policy,
          policy_version: authorization_evidence.policy_version
        )
        @evaluator.call(authorization_command, decided_at: recorded_at)
      end

      def verify_event_plan!(plan, history:, command:)
        result = @event_plan_contract.call(
          plan:,
          history:,
          command:
        )
        return if result.success?

        raise InvalidMergeObservationEventPlan, result.errors.to_h.inspect
      end

      def persist_plan(plan, command:, preparation:, observation_digest:, caused_by:)
        ids = [ preparation.observation_event_id, preparation.authorization_link_event_id ]
        parent = caused_by
        correlation_id = caused_by&.correlation_id || preparation.correlation_id
        plan.writes.zip(ids).map do |write, event_id|
          physical = @event_factory.build!(
            event: write.event,
            event_id:,
            metadata: event_metadata(write.event, command, observation_digest),
            markers: event_markers(command, observation_digest),
            caused_by: parent,
            correlation_id:
          )
          persisted = @event_store.append(write.stream, [ physical ]).sole
          parent = persisted
          persisted
        end
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

      def event_markers(command, observation_digest)
        [
          "merge-snapshot:#{command.merge_snapshot_id}",
          "merge-observation:#{observation_digest}",
          "merge-authorization:#{command.authorization_event.stream_id}",
          "repository:#{command.repository_id}",
          "target-branch:#{command.target_branch}",
          "merge-snapshot-status:observed",
          "command:#{command.command_id}"
        ]
      end

      def root_correlation_id(preparation, caused_by)
        preparation.correlation_id unless caused_by
      end

      def event_metadata(event, command, observation_digest)
        attributes = {
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: command.policy_version
        }
        case event
        when Events::MergeObservedV2
          Metadata::MergeObservationV2.new(
            **attributes,
            authorization_decision_digest: command.authorization_decision_digest,
            observation_digest:
          )
        when Events::MergeObservationAuthorizationLinkedV1
          EventMetadata.new(**attributes)
        else
          raise "Unexpected merge observation event #{event.class.name}"
        end
      end

      def metadata_expected_policy(metadata)
        value = metadata["expected_impact_policy"]
        return unless value

        MergeAuthorizations::ExpectedImpactPolicyV1.new(deep_symbolize(value))
      end

      def deep_symbolize(value)
        case value
        when Hash then value.to_h { |key, nested| [ key.to_sym, deep_symbolize(nested) ] }
        when Array then value.map { deep_symbolize(_1) }
        else value
        end
      end
    end
  end
end
