# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class DevelopmentArtifactContextResolver
      include Dry::Monads[:result]

      SOURCE_TYPES = {
        "DevelopmentArtifactCaptured" => LegacyEvents::DevelopmentArtifactCapturedV2,
        "DevelopmentArtifactObserved" => LegacyEvents::DevelopmentArtifactObservedV1,
        "DevelopmentArtifactClassificationCorrected" =>
          LegacyEvents::DevelopmentArtifactClassificationCorrectedV1
      }.freeze
      OBSERVATION_TYPES = %w[
        DevelopmentArtifactObserved DevelopmentArtifactClassificationCorrected
      ].freeze
      SOURCE_HISTORY_PAGE_SIZE = 1_000

      def initialize(
        event_store:,
        stream_identity_allocator:,
        state_transition: DevelopmentArtifactStateTransition.new,
        schema_registry: LegacyEventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_identity_allocator = stream_identity_allocator
        @state_transition = state_transition
        @schema_registry = schema_registry
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        validate_envelope!(source_event, source_payload, source_upper_position:)
        legacy_artifact_id = artifact_id(source_payload)
        captured_event, captured = captured_source(legacy_artifact_id, source_upper_position:)
        state = prior_state(
          captured_event:,
          captured:,
          source_event:,
          source_upper_position:
        )
        artifact_allocation = allocate(
          migration_id:,
          source_config_name:,
          source_event: captured_event,
          target_stream_name: "DevelopmentArtifact",
          identity_role: "development-artifact"
        )
        return artifact_allocation if artifact_allocation.failure?

        observation = observation_context(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_payload:
        )
        return observation if observation.failure?

        artifact_stream = artifact_allocation.value!.target_stream
        observation_stream = observation.value!
        Success(
          DevelopmentArtifactMigrationContextV1.new(
            artifact_stream:,
            artifact_id: artifact_stream.stream_id,
            observation_stream:,
            observation_id: observation_stream&.stream_id,
            state:
          )
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error, EventHistoryLimitExceeded => error
        Failure(inconsistent(source_event, error.message))
      end

      private

      def validate_envelope!(source_event, source_payload, source_upper_position:)
        expected = SOURCE_TYPES.fetch(source_event.type)
        valid = source_payload.is_a?(expected) &&
                source_event.metadata.fetch("schema_version") == expected.schema_version &&
                source_event.global_position <= source_upper_position &&
                source_event.stream.context == "DevelopmentMemory" &&
                source_event.markers.include?("development-artifact:#{artifact_id(source_payload)}")
        raise ArgumentError, "source identity, schema, or marker is invalid" unless valid

        case source_payload
        when LegacyEvents::DevelopmentArtifactCapturedV2
          valid = source_event.stream.stream_name == "DevelopmentArtifact" &&
                  source_event.stream.stream_id == source_payload.artifact.artifact_id &&
                  source_event.stream_revision.zero?
        when LegacyEvents::DevelopmentArtifactObservedV1
          valid = source_event.stream.stream_name == "DevelopmentArtifactObservation" &&
                  source_event.stream.stream_id == source_payload.observation.observation_id &&
                  source_event.stream_revision.zero?
        when LegacyEvents::DevelopmentArtifactClassificationCorrectedV1
          valid = source_event.stream.stream_name == "DevelopmentArtifactObservation" &&
                  source_event.stream.stream_id == source_payload.observation_id &&
                  source_event.stream_revision == source_payload.classification_revision - 1
        end
        raise ArgumentError, "source stream lifecycle is invalid" unless valid

        validate_observation_lifecycle!(source_event, source_payload) unless
          source_payload.is_a?(LegacyEvents::DevelopmentArtifactCapturedV2)
      end

      def validate_observation_lifecycle!(source_event, source_payload)
        history = @event_store.read(
          stream_for(source_event),
          EventReadCriteria.new(
            event_types: OBSERVATION_TYPES,
            maximum_count: Types::DEVELOPMENT_ARTIFACT_CLASSIFICATION_MAXIMUM_REVISIONS,
            direction: :asc,
            to_revision: source_event.stream_revision
          )
        )
        valid = history.last&.id == source_event.id &&
                history.first&.type == "DevelopmentArtifactObserved" &&
                history.each_with_index.all? do |event, index|
                  payload = load(event)
                  if index.zero?
                    payload.is_a?(LegacyEvents::DevelopmentArtifactObservedV1) &&
                      payload.observation.observation_id == source_event.stream.stream_id
                  else
                    payload.is_a?(LegacyEvents::DevelopmentArtifactClassificationCorrectedV1) &&
                      payload.observation_id == source_event.stream.stream_id &&
                      payload.classification_revision == index + 1
                  end
                end
        valid &&= artifact_id(load(history.first)) == artifact_id(source_payload)
        raise ArgumentError, "observation lifecycle is not sequential" unless valid
      end

      def captured_source(legacy_artifact_id, source_upper_position:)
        event = @event_store.read_at(
          StreamReference.new(
            context: "DevelopmentMemory",
            stream_name: "DevelopmentArtifact",
            stream_id: legacy_artifact_id
          ),
          0
        )
        payload = event && load(event)
        valid = event &&
                event.global_position <= source_upper_position &&
                payload.is_a?(LegacyEvents::DevelopmentArtifactCapturedV2) &&
                payload.artifact.artifact_id == legacy_artifact_id &&
                event.markers.include?("development-artifact:#{legacy_artifact_id}")
        raise ArgumentError, "captured Artifact source is absent or inconsistent" unless valid

        [ event, payload ]
      end

      def prior_state(captured_event:, captured:, source_event:, source_upper_position:)
        state = initial_state(captured_event, captured)
        return state if source_event.id == captured_event.id

        upper = [ source_event.global_position - 1, source_upper_position ].min
        return state if upper.negative?

        prior_observation_events(captured.artifact.artifact_id, upper:).each do |event|
          payload = load(event)
          validate_transition!(event, payload, captured.artifact.artifact_id)
          state = @state_transition.call(state:, source: payload, source_event: event).state
        end
        state
      end

      def prior_observation_events(legacy_artifact_id, upper:)
        OBSERVATION_TYPES.flat_map do |event_type|
          observation_pages(legacy_artifact_id, event_type:, upper:)
        end.sort_by(&:global_position)
      end

      def observation_pages(legacy_artifact_id, event_type:, upper:)
        events = []
        from_position = 0
        loop do
          rows = @event_store.read_global_marked_page(
            GlobalMarkedEventPageCriteria.new(
              stream_context: "DevelopmentMemory",
              stream_name: "DevelopmentArtifactObservation",
              event_type:,
              markers: [ "development-artifact:#{legacy_artifact_id}" ],
              from_position:,
              to_position: upper,
              page_size: SOURCE_HISTORY_PAGE_SIZE,
              direction: :asc
            )
          )
          page = rows.first(SOURCE_HISTORY_PAGE_SIZE)
          events.concat(page)
          break if rows.length <= SOURCE_HISTORY_PAGE_SIZE

          from_position = page.last.global_position + 1
        end
        events
      end

      def validate_transition!(event, payload, legacy_artifact_id)
        valid = SOURCE_TYPES.fetch(event.type) == payload.class &&
                event.metadata.fetch("schema_version") == payload.class.schema_version &&
                artifact_id(payload) == legacy_artifact_id &&
                event.stream.stream_id == observation_id(payload)
        raise ArgumentError, "prior Artifact observation transition is invalid" unless valid
      end

      def initial_state(event, source)
        artifact = source.artifact
        reference = event_reference(event)
        DevelopmentArtifactSourceStateV1.new(
          legacy_artifact_id: artifact.artifact_id,
          scope: artifact.scope,
          title: artifact.title,
          kind: artifact.kind,
          source: artifact.source,
          content: artifact.content,
          created_origin: origin("created", "DevelopmentArtifactCreated", DevelopmentArtifactPropertySteps.created, reference),
          scope_origin: origin(
            "scope", "DevelopmentArtifactScopeChanged",
            DevelopmentArtifactPropertySteps.property("scope", "initial"), reference
          ),
          title_origin: origin(
            "title", "DevelopmentArtifactTitleChanged",
            DevelopmentArtifactPropertySteps.property("title", "initial"), reference
          ),
          kind_origin: origin(
            "kind", "DevelopmentArtifactKindChanged",
            DevelopmentArtifactPropertySteps.property("kind", "initial"), reference
          ),
          source_origin: origin(
            "source", "DevelopmentArtifactSourceChanged",
            DevelopmentArtifactPropertySteps.property("source", "initial"), reference
          ),
          content_origin: origin(
            "content", "DevelopmentArtifactContentChanged",
            DevelopmentArtifactPropertySteps.content, reference
          ),
          labels: artifact.labels.each_with_index.map do |label, index|
            DevelopmentArtifactLabelStateV1.new(
              label:,
              origin: origin(
                "label", "DevelopmentArtifactLabelAdded",
                DevelopmentArtifactPropertySteps.label_added("initial", index), reference
              )
            )
          end.freeze
        )
      end

      def observation_context(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_payload:
      )
        return Success(nil) if source_payload.is_a?(LegacyEvents::DevelopmentArtifactCapturedV2)

        root = source_payload.is_a?(LegacyEvents::DevelopmentArtifactObservedV1) ?
          source_event : @event_store.read_at(stream_for(source_event), 0)
        valid = root && root.global_position <= source_upper_position &&
                load(root).is_a?(LegacyEvents::DevelopmentArtifactObservedV1)
        raise ArgumentError, "observation root is absent" unless valid

        allocate(
          migration_id:,
          source_config_name:,
          source_event: root,
          target_stream_name: "DevelopmentArtifactObservation",
          identity_role: "development-artifact-observation"
        ).fmap(&:target_stream)
      end

      def allocate(
        migration_id:,
        source_config_name:,
        source_event:,
        target_stream_name:,
        identity_role:
      )
        @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_context: "DevelopmentMemory",
          target_stream_name:,
          identity_role:
        )
      end

      def artifact_id(payload)
        case payload
        when LegacyEvents::DevelopmentArtifactCapturedV2 then payload.artifact.artifact_id
        when LegacyEvents::DevelopmentArtifactObservedV1 then payload.observation.artifact_id
        when LegacyEvents::DevelopmentArtifactClassificationCorrectedV1 then payload.artifact_id
        end
      end

      def observation_id(payload)
        case payload
        when LegacyEvents::DevelopmentArtifactObservedV1 then payload.observation.observation_id
        when LegacyEvents::DevelopmentArtifactClassificationCorrectedV1 then payload.observation_id
        end
      end

      def origin(role, event_type, step_name, source_event)
        DevelopmentArtifactPropertyOriginV1.new(role:, event_type:, step_name:, source_event:)
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

      def stream_for(event)
        StreamReference.new(
          context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id
        )
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Development Artifact source is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
