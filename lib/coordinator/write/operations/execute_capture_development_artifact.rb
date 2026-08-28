# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteCaptureDevelopmentArtifact < Dry::Operation
      TOOL_NAME = "development_artifact_capture"

      def initialize(
        event_store:,
        preparer: PrepareCaptureDevelopmentArtifact.new,
        loader: DevelopmentArtifacts::Loader.new(event_store:),
        decider: Domain::DevelopmentArtifacts::Capture.new,
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
        DevelopmentArtifactCapturePreparationV1.new(
          captured_at: @clock.now,
          input_digest: @input_digest.development_artifact_capture(command),
          capture_event_id: @id_generator.uuid_v7,
          observation_event_id: @id_generator.uuid_v7,
          completion_event_id: @id_generator.uuid_v7
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        replay = replay_result(command:, input_digest: preparation.input_digest)
        return replay if replay

        decision_result = @decider.call(
          state: @loader.load(command.artifact.artifact_id),
          observation_state: @loader.load_observation(command.observation.observation_id),
          command:,
          captured_at: preparation.captured_at
        )
        return decision_result if decision_result.failure?

        decision = decision_result.value!
        persisted_events = persist_domain_plan(
          decision.event_plan,
          command:,
          preparation:,
          caused_by:
        )
        completion = @completion_builder.development_artifact_capture(
          command:,
          decision:,
          input_digest: preparation.input_digest,
          persisted_events:,
          completed_at: preparation.captured_at
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
          Failure(command_id_reused(command, completion:, input_digest:))
        end
      end

      def command_id_reused(command, completion:, input_digest:)
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

      def persist_domain_plan(plan, command:, preparation:, caused_by:)
        return [] unless plan

        expected_streams = [
          @stream_factory.development_artifact(command.artifact.artifact_id),
          @stream_factory.development_artifact_observation(command.observation.observation_id)
        ]
        unless plan.writes.length.between?(1, 2) &&
               plan.writes.map(&:stream).uniq.length == plan.writes.length &&
               plan.writes.all? { expected_streams.include?(_1.stream) }
          raise "CaptureDevelopmentArtifact domain plan must write bounded Artifact and observation facts"
        end

        plan.writes.flat_map do |write|
          event = write.event
          persisted = @event_factory.build!(
            event:,
            event_id: domain_event_id(event, preparation),
            metadata: command_metadata(command),
            markers: @marker_builder.capture(event:, command_id: command.command_id),
            caused_by:
          )
          @event_store.append(write.stream, [ persisted ])
        end
      end

      def domain_event_id(event, preparation)
        case event
        when Events::DevelopmentArtifactCapturedV1 then preparation.capture_event_id
        when Events::DevelopmentArtifactObservedV1 then preparation.observation_event_id
        else raise "Unexpected Development Artifact capture event #{event.class.name}"
        end
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
