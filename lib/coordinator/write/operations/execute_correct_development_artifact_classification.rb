# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteCorrectDevelopmentArtifactClassification < Dry::Operation
      TOOL_NAME = "development_artifact_classification_correct"

      def initialize(
        event_store:,
        preparer: PrepareCorrectDevelopmentArtifactClassification.new,
        loader: DevelopmentArtifacts::Loader.new(event_store:),
        decider: Domain::DevelopmentArtifacts::CorrectClassificationV2.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
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
          fact_event_ids: (2 + Types::DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_COUNT * 2).times.map { @id_generator.uuid_v7 },
          link_event_ids: (2 + Types::DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_COUNT * 2).times.map { @id_generator.uuid_v7 }
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        observation_state = @loader.load_observation(command.observation_id)
        artifact_id = observation_state.artifact_id
        artifact_state, artifact_revision = artifact_id ? @loader.load_with_revision(artifact_id) : [ nil, -1 ]
        fact_references = artifact_id ?
          proposed_fact_references(artifact_id, command, artifact_state, artifact_revision, preparation) : []
        decision_result = @decider.call(
          state: observation_state,
          artifact_state:,
          command:,
          fact_event_references: fact_references
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
          preparation:,
          caused_by:
        )
        completion = @completion_builder.development_artifact_classification_correct(
          command:,
          decision:,
          input_digest: preparation.input_digest,
          persisted_events:,
          completed_at: preparation.corrected_at
        )

        Success(completion)
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

        fact_index = 0
        link_index = 0
        plan.writes.flat_map do |write|
          event = write.event
          event_id = case event
          when Events::DevelopmentArtifactClassificationCorrectionRecordedV1
            preparation.correction_event_id
          when Events::DevelopmentArtifactObservationFactLinkedV1
            preparation.link_event_ids.fetch(link_index).tap { link_index += 1 }
          else
            preparation.fact_event_ids.fetch(fact_index).tap { fact_index += 1 }
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

      def proposed_fact_references(artifact_id, command, artifact_state, artifact_revision, preparation)
        return [] unless artifact_state

        current_title = value_of(artifact_state.title, :title)
        current_kind = value_of(artifact_state.kind, :kind)
        current_labels = Array(artifact_state.labels)
        requested_labels = command.labels.uniq.sort_by(&:b)
        fact_types = []
        fact_types << "DevelopmentArtifactTitleChanged" if current_title != command.title
        fact_types << "DevelopmentArtifactKindChanged" if current_kind != command.kind
        fact_types.concat(Array.new((requested_labels - current_labels).length, "DevelopmentArtifactLabelAdded"))
        fact_types.concat(Array.new((current_labels - requested_labels).length, "DevelopmentArtifactLabelRemoved"))
        return [] if fact_types.empty?

        stream = @stream_factory.development_artifact(artifact_id)
        fact_types.each_with_index.map do |type, index|
          EventReference.new(
            event_id: preparation.fact_event_ids.fetch(index),
            type:,
            stream_context: stream.context,
            stream_name: stream.stream_name,
            stream_id: stream.stream_id,
            stream_revision: artifact_revision + index + 1
          )
        end
      end

      def value_of(value, attribute)
        value&.public_send(attribute)
      end

      def event_metadata(event, command)
        if event.is_a?(Events::DevelopmentArtifactClassificationCorrectionRecordedV1)
          Metadata::ClassifierV1.new(**command_metadata(command).to_h, classifier: command.actor.id)
        else
          command_metadata(command)
        end
      end

      def event_markers(event, command)
        if event.is_a?(Events::DevelopmentArtifactObservationFactLinkedV1) ||
           event.is_a?(Events::DevelopmentArtifactClassificationCorrectionRecordedV1)
          @marker_builder.classification(event:, command_id: command.command_id)
        else
          @marker_builder.artifact(event:, command_id: command.command_id)
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
