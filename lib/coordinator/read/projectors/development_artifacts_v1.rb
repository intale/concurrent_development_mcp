# frozen_string_literal: true

module Coordinator::Read
  module Projectors
    class DevelopmentArtifactsV1
      PROJECTION = ProjectionDefinition.new(name: "development-artifacts", version: 1)

      def initialize(
        contract: Contracts::DevelopmentArtifactSourceEvent.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        artifacts: Repositories::DevelopmentArtifacts.new,
        processed_events: Repositories::ProcessedProjectionEvents.new
      )
        @contract = contract
        @schema_registry = schema_registry
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
            processed_at: Time.now.utc
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
          when Coordinator::Write::Events::DevelopmentArtifactCapturedV1
            domain_event.artifact.artifact_id
          when Coordinator::Write::Events::DevelopmentArtifactRelationDeclaredV1
            domain_event.artifact_relation.source_artifact_id
          end
        return if event.stream.stream_id == artifact_id

        raise InvalidProjectionSource, "Artifact payload does not match its source stream"
      end

      def project(event, domain_event)
        case domain_event
        when Coordinator::Write::Events::DevelopmentArtifactCapturedV1
          @artifacts.store_capture(event:, capture: domain_event)
        when Coordinator::Write::Events::DevelopmentArtifactRelationDeclaredV1
          @artifacts.store_relation(event:, declaration: domain_event)
        else
          raise InvalidProjectionSource, "Unsupported Artifact event #{domain_event.class.name}"
        end
      end
    end
  end
end
