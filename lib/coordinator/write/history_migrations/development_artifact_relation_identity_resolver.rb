# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class DevelopmentArtifactRelationIdentityResolver
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        stream_identity_allocator:,
        schema_registry: LegacyEventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_identity_allocator = stream_identity_allocator
        @schema_registry = schema_registry
      end

      def call(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_relation_id:,
        source_artifact_id:
      )
        declaration_event = declaration_event(
          source_relation_id,
          source_upper_position:
        )
        declaration = declaration_event && load(declaration_event)
        validate_declaration!(
          declaration_event,
          declaration,
          source_relation_id:,
          source_artifact_id:,
          source_upper_position:
        )
        validate_artifact_root!(
          declaration_event,
          source_artifact_id:,
          source_upper_position:
        )

        @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event: declaration_event,
          target_stream_context: "DevelopmentMemory",
          target_stream_name: "DevelopmentArtifactRelation",
          identity_role: "development-artifact-relation-#{declaration_event.stream_revision}"
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error,
             EventHistoryLimitExceeded, EventSchemaRegistry::UnknownSchema,
             EventSchemaRegistry::SchemaMismatch => error
        Failure(invalid(source_event, error.message))
      end

      private

      def declaration_event(source_relation_id, source_upper_position:)
        events = @event_store.read_global_marked(
          GlobalMarkedEventReadCriteria.new(
            stream_context: "DevelopmentMemory",
            stream_name: "DevelopmentArtifact",
            event_types: [ "DevelopmentArtifactRelationDeclared" ],
            markers: [ "development-artifact-relation:#{source_relation_id}" ],
            maximum_count: 2,
            direction: :asc,
            to_position: source_upper_position
          )
        )
        events.one? ? events.first : nil
      end

      def validate_declaration!(
        event,
        payload,
        source_relation_id:,
        source_artifact_id:,
        source_upper_position:
      )
        relation = payload&.artifact_relation
        valid = event &&
                event.global_position <= source_upper_position &&
                event.stream.context == "DevelopmentMemory" &&
                event.stream.stream_name == "DevelopmentArtifact" &&
                event.stream.stream_id == source_artifact_id &&
                event.stream_revision.positive? &&
                payload.is_a?(LegacyEvents::DevelopmentArtifactRelationDeclaredV1) &&
                relation.relation_id == source_relation_id &&
                relation.source_artifact_id == source_artifact_id &&
                event.markers.include?("development-artifact:#{source_artifact_id}") &&
                event.markers.include?("development-artifact-relation:#{source_relation_id}")
        raise ArgumentError, "relation declaration is absent or inconsistent" unless valid
      end

      def validate_artifact_root!(declaration_event, source_artifact_id:, source_upper_position:)
        root = @event_store.read_at(stream_for(declaration_event), 0)
        payload = root && load(root)
        valid = root &&
                root.global_position <= source_upper_position &&
                root.global_position < declaration_event.global_position &&
                payload.is_a?(LegacyEvents::DevelopmentArtifactCapturedV2) &&
                payload.artifact.artifact_id == source_artifact_id &&
                root.markers.include?("development-artifact:#{source_artifact_id}")
        raise ArgumentError, "captured Artifact source is absent or inconsistent" unless valid
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

      def invalid(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Development Artifact relation identity is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
