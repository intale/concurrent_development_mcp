# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteCorrectDevelopmentArtifactClassification < Dry::Operation
      TOOL_NAME = "development_artifact_classification_correct"

      def initialize(
        event_store:,
        preparer: PrepareCorrectDevelopmentArtifactClassification.new,
        loader: DevelopmentArtifacts::Loader.new(event_store:),
        decider: Domain::DevelopmentArtifacts::CorrectClassification.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        marker_builder: DevelopmentArtifacts::MarkerBuilder.new,
        completion_builder: CommandCompletionBuilder.new
      )
        @event_store = event_store
        @preparer = preparer
        @loader = loader
        @decider = decider
        @input_digest = input_digest
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @marker_builder = marker_builder
        @completion_builder = completion_builder
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
        DevelopmentArtifactClassificationPreparationV1.new(
          corrected_at: @clock.now,
          input_digest: @input_digest.development_artifact_classification_correct(command),
          correction_event_id: @id_generator.uuid_v7,
          completion_event_id: @id_generator.uuid_v7
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        replay = replay_result(command:, input_digest: preparation.input_digest)
        return replay if replay

        decision_result = @decider.call(
          state: @loader.load_observation(command.observation_id),
          command:,
          corrected_at: preparation.corrected_at
        )
        return decision_result if decision_result.failure?

        decision = decision_result.value!
        ActiveSupport::Notifications.instrument(
          "coordinator.command_boundary",
          operation: TOOL_NAME,
          command_id: command.command_id
        )
        persisted_events = persist_domain_plan(
          decision.event_plan,
          command:,
          event_id: preparation.correction_event_id,
          caused_by:
        )
        completion = @completion_builder.development_artifact_classification_correct(
          command:,
          decision:,
          input_digest: preparation.input_digest,
          persisted_events:,
          completed_at: preparation.corrected_at
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
        event && load_event(event)
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def persist_domain_plan(plan, command:, event_id:, caused_by:)
        return [] unless plan

        expected_stream = @stream_factory.development_artifact_observation(command.observation_id)
        unless plan.writes.length == 1 && plan.writes.first.stream == expected_stream
          raise "CorrectDevelopmentArtifactClassification domain plan must write one observation fact"
        end

        event = plan.writes.first.event
        persisted = @event_factory.build!(
          event:,
          event_id:,
          metadata: command_metadata(command),
          markers: @marker_builder.classification(event:, command_id: command.command_id),
          caused_by:
        )
        @event_store.append(expected_stream, [ persisted ])
      end

      def persist_completion(completion, command:, event_id:, caused_by:)
        persisted = @event_factory.build!(
          event: completion,
          event_id:,
          metadata: command_metadata(command),
          markers: [ "command:#{command.command_id}" ],
          caused_by:
        )
        @event_store.append(@stream_factory.command(command.command_id), [ persisted ])
      end

      def command_metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: "development-artifact-repository/v1"
        )
      end
    end
  end
end
