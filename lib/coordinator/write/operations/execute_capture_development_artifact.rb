# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteCaptureDevelopmentArtifact < Dry::Operation
      TOOL_NAME = "development_artifact_capture"

      def initialize(
        event_store:,
        preparer: PrepareCaptureDevelopmentArtifact.new,
        loader: DevelopmentArtifacts::Loader.new(event_store:),
        decider: Domain::DevelopmentArtifacts::GranularCapture.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        stream_factory: StreamFactory.new,
        marker_builder: DevelopmentArtifacts::MarkerBuilder.new,
        completion_builder: CommandResultBuilder.new
      )
        @event_store = event_store
        @preparer = preparer
        @loader = loader
        @decider = decider
        @input_digest = input_digest
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
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
        fact_count = 6 + command.artifact.labels.length
        DevelopmentArtifactCapturePreparationV1.new(
          captured_at: @clock.now,
          input_digest: @input_digest.development_artifact_capture(command),
          observation_event_id: @id_generator.uuid_v7,
          artifact_fact_event_ids: fact_count.times.map { @id_generator.uuid_v7 },
          observation_fact_event_ids: fact_count.times.map { @id_generator.uuid_v7 }
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        state = @loader.load(command.artifact.artifact_id)
        return Failure(OutcomeError.new(
          code: :development_artifact_identity_conflict,
          message: "Artifact UUIDv7 is already occupied",
          details: { artifact_id: command.artifact.artifact_id }
        )) if state.created

        fact_references = proposed_fact_references(command.artifact.artifact_id, command, preparation)
        decision_result = @decider.call(
          artifact: command.artifact,
          observation: command.observation,
          fact_event_references: fact_references
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

        Success(completion)
      end

      def persist_domain_plan(plan, command:, preparation:, caused_by:)
        return [] unless plan

        artifact_index = 0
        observation_index = 0
        plan.writes.flat_map do |write|
          event = write.event
          event_id = if event.is_a?(Events::DevelopmentArtifactObservationRecordedV1)
            preparation.observation_event_id
          elsif event.is_a?(Events::DevelopmentArtifactObservationFactLinkedV1)
            preparation.observation_fact_event_ids.fetch(observation_index).tap { observation_index += 1 }
          else
            preparation.artifact_fact_event_ids.fetch(artifact_index).tap { artifact_index += 1 }
          end
          persisted = @event_factory.build!(
            event:,
            event_id:,
            metadata: event_metadata(event, command),
            markers: event_markers(event, command),
            caused_by:
          )
          @event_store.append(write.stream, [ persisted ])
        end
      end

      def proposed_fact_references(artifact_id, command, preparation)
        types = [
          "DevelopmentArtifactCreated", "DevelopmentArtifactScopeChanged",
          "DevelopmentArtifactTitleChanged", "DevelopmentArtifactKindChanged",
          "DevelopmentArtifactSourceChanged", "DevelopmentArtifactContentChanged"
        ] + Array.new(command.artifact.labels.length, "DevelopmentArtifactLabelAdded")
        types.each_with_index.map do |type, index|
          EventReference.new(
            event_id: preparation.artifact_fact_event_ids.fetch(index), type:,
            stream_context: "DevelopmentMemory", stream_name: "DevelopmentArtifact",
            stream_id: artifact_id, stream_revision: index
          )
        end
      end

      def event_metadata(event, command)
        case event
        when Events::DevelopmentArtifactContentChangedV1
          Metadata::ContentV1.new(
            **command_metadata(command).to_h,
            **content_metadata(command.artifact.content)
          )
        when Events::DevelopmentArtifactSourceChangedV1
          Metadata::CollectorV1.new(
            **command_metadata(command).to_h,
            collector: command.artifact.source.collector
          )
        else
          command_metadata(command)
        end
      end

      def content_metadata(content)
        {
          encoding: content.encoding,
          media_type: content.media_type,
          byte_size: content.byte_size,
          content_sha256: content.content_sha256
        }
      end

      def event_markers(event, command)
        if event.is_a?(Events::DevelopmentArtifactObservationRecordedV1) ||
           event.is_a?(Events::DevelopmentArtifactObservationFactLinkedV1)
          @marker_builder.observation(event:, command_id: command.command_id)
        else
          @marker_builder.artifact(
            event:,
            command_id: command.command_id,
            natural_key: event.is_a?(Events::DevelopmentArtifactCreatedV1) ?
              @marker_builder.natural_key(command.artifact) : nil
          )
        end
      end

      def command_metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: "development-artifact-repository/v2"
        )
      end
    end
  end
end
