# frozen_string_literal: true

module Coordinator::Read
  module Projectors
    class DevelopmentArtifactsV1
      PROJECTION = ProjectionDefinition.new(name: "development-artifacts", version: 5)

      def initialize(
        contract: Contracts::DevelopmentArtifactSourceEvent.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        event_store:,
        artifacts: Repositories::DevelopmentArtifacts.new,
        processed_events: Repositories::ProcessedProjectionEvents.new
      )
        @contract = contract
        @schema_registry = schema_registry
        @event_store = event_store
        @artifacts = artifacts
        @processed_events = processed_events
      end

      def call(event)
        domain_event = load_domain_event(event)
        verify_stream_identity!(event, domain_event)
        identity = ProjectionEventIdentity.from_event(event)

        ApplicationRecord.transaction do
          next unless @processed_events.claim(
            definition: PROJECTION,
            identity:,
            processed_at: event.created_at
          )

          project(event, domain_event)
        end

        nil
      end

      private

      def load_domain_event(event)
        result = @contract.call(
          event_type: event.type,
          schema_version: event.metadata["schema_version"],
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision,
          global_position: event.global_position,
          command_id: event.metadata["command_id"],
          actor_kind: event.metadata["actor_kind"],
          actor_id: event.metadata["actor_id"],
          recorded_by: event.metadata["recorded_by"],
          policy_version: event.metadata["policy_version"]
        )
        raise InvalidProjectionSource, result.errors.to_h.inspect if result.failure?

        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def verify_stream_identity!(event, domain_event)
        artifact_id =
          case domain_event
          when Coordinator::Write::Events::DevelopmentArtifactCreatedV1,
               Coordinator::Write::Events::DevelopmentArtifactScopeChangedV1,
               Coordinator::Write::Events::DevelopmentArtifactTitleChangedV1,
               Coordinator::Write::Events::DevelopmentArtifactKindChangedV1,
               Coordinator::Write::Events::DevelopmentArtifactLabelAddedV1,
               Coordinator::Write::Events::DevelopmentArtifactLabelRemovedV1,
               Coordinator::Write::Events::DevelopmentArtifactSourceChangedV1,
               Coordinator::Write::Events::DevelopmentArtifactContentChangedV1
            domain_event.artifact_id
          when Coordinator::Write::Events::DevelopmentArtifactObservationRecordedV1,
               Coordinator::Write::Events::DevelopmentArtifactObservationFactLinkedV1,
               Coordinator::Write::Events::DevelopmentArtifactClassificationCorrectionRecordedV1
            domain_event.observation_id
          when Coordinator::Write::Events::DevelopmentArtifactRelationDeclaredV2
            domain_event.relation_id
          when Coordinator::Write::Events::DevelopmentArtifactRelationSupersededV2
            domain_event.relation_id
          end
        return if event.stream.stream_id == artifact_id

        raise InvalidProjectionSource, "Artifact payload does not match its source stream"
      end

      def project(event, domain_event)
        case domain_event
        when Coordinator::Write::Events::DevelopmentArtifactCreatedV1
            @artifacts.store_created(event:, created: domain_event)
        when Coordinator::Write::Events::DevelopmentArtifactScopeChangedV1,
               Coordinator::Write::Events::DevelopmentArtifactTitleChangedV1,
               Coordinator::Write::Events::DevelopmentArtifactKindChangedV1,
               Coordinator::Write::Events::DevelopmentArtifactLabelAddedV1,
               Coordinator::Write::Events::DevelopmentArtifactLabelRemovedV1,
               Coordinator::Write::Events::DevelopmentArtifactSourceChangedV1,
               Coordinator::Write::Events::DevelopmentArtifactContentChangedV1
            @artifacts.store_property(event:, fact: domain_event)
        when Coordinator::Write::Events::DevelopmentArtifactObservationRecordedV1
            @artifacts.store_observation_recorded(event:, recorded: domain_event)
        when Coordinator::Write::Events::DevelopmentArtifactObservationFactLinkedV1
            fact_event, fact = resolve_observed_fact(domain_event)
            @artifacts.store_observation_fact_link(
              event:,
              link: domain_event,
              observed_fact_event: fact_event,
              observed_fact: fact
            )
        when Coordinator::Write::Events::DevelopmentArtifactClassificationCorrectionRecordedV1
            @artifacts.store_classification_recorded(event:, correction: domain_event)
        when Coordinator::Write::Events::DevelopmentArtifactRelationDeclaredV2
            @artifacts.store_relation_v2(event:, declaration: domain_event)
        when Coordinator::Write::Events::DevelopmentArtifactRelationSupersededV2
            @artifacts.store_supersession_v2(event:, supersession: domain_event)
        else
          raise InvalidProjectionSource, "Unsupported Artifact event #{domain_event.class.name}"
        end
      end

      def resolve_observed_fact(link)
        reference = link.observed_fact
        fact_event = @event_store.read_at(
          Coordinator::Write::StreamReference.new(
            context: reference.stream_context,
            stream_name: reference.stream_name,
            stream_id: reference.stream_id
          ),
          reference.stream_revision
        )
        unless fact_event &&
               fact_event.id == reference.event_id &&
               fact_event.type == reference.type &&
               fact_event.stream.stream_id == reference.stream_id &&
               fact_event.stream_revision == reference.stream_revision
          raise InvalidProjectionSource, "Observation fact reference could not be resolved"
        end

        fact = @schema_registry.load(
          type: fact_event.type,
          schema_version: fact_event.metadata.fetch("schema_version"),
          data: fact_event.data
        )
        [ fact_event, fact ]
      end
    end
  end
end
