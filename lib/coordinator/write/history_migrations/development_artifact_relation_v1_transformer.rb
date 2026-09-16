# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class DevelopmentArtifactRelationV1Transformer
      include Dry::Monads[:result]

      SOURCE_TYPES = {
        "DevelopmentArtifactRelationDeclared" => LegacyEvents::DevelopmentArtifactRelationDeclaredV1,
        "DevelopmentArtifactRelationSuperseded" => LegacyEvents::DevelopmentArtifactRelationSupersededV1
      }.freeze
      TARGET_STREAMS = {
        "artifact" => [ "DevelopmentMemory", "DevelopmentArtifact", "development-artifact" ],
        "change_set" => [ "DevelopmentPlanning", "ChangeSet", "change-set" ],
        "work_item" => [ "DevelopmentExecution", "WorkItem", "work-item" ],
        "attempt" => [ "DevelopmentExecution", "Attempt", "attempt" ],
        "candidate" => [ "DevelopmentIntegration", "Candidate", "candidate" ],
        "decision" => [ "HumanGuidance", "Decision", "decision" ],
        "skill" => [ "AgentKnowledge", "Skill", "skill" ],
        "repository" => [ "DevelopmentPlanning", "Repository", "repository" ],
        "resource" => [ "DevelopmentCoordination", "Resource", "resource" ],
        "operation_batch" => [ "DevelopmentCoordination", "OperationBatch", "operation-batch" ]
      }.freeze

      def initialize(
        event_store:,
        stream_identity_allocator:,
        entity_reference_resolver:,
        schema_registry: LegacyEventSchemaRegistry.new,
        marker_builder: DevelopmentArtifacts::MarkerBuilder.new
      )
        @event_store = event_store
        @stream_identity_allocator = stream_identity_allocator
        @entity_reference_resolver = entity_reference_resolver
        @schema_registry = schema_registry
        @marker_builder = marker_builder
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        validate_envelope!(source_event, source_payload, source_upper_position:)
        source_artifact = resolve_entity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          kind: "artifact",
          source_id: source_artifact_id(source_payload)
        )
        return source_artifact if source_artifact.failure?

        case source_payload
        when LegacyEvents::DevelopmentArtifactRelationDeclaredV1
          declared(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload,
            source_artifact_id: source_artifact.value!
          )
        when LegacyEvents::DevelopmentArtifactRelationSupersededV1
          superseded(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload,
            source_artifact_id: source_artifact.value!
          )
        end
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error,
             EventHistoryLimitExceeded, EventSchemaRegistry::UnknownSchema,
             EventSchemaRegistry::SchemaMismatch => error
        Failure(inconsistent(source_event, error.message))
      end

      private

      def declared(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        source_artifact_id:
      )
        relation_allocation = allocate_relation(
          migration_id:,
          source_config_name:,
          declaration_event: source_event
        )
        return relation_allocation if relation_allocation.failure?

        target = resolve_target(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_target: source.artifact_relation.target
        )
        return target if target.failure?

        target_stream = relation_allocation.value!.target_stream
        relation = DevelopmentArtifacts::RelationV1.new(
          relation_id: target_stream.stream_id,
          source_artifact_id:,
          relation: source.artifact_relation.relation,
          target: target.value!,
          attributes: source.artifact_relation.relation_attributes
        )
        event = Events::DevelopmentArtifactRelationDeclaredV2.new(
          relation_id: relation.relation_id,
          source_artifact_id: relation.source_artifact_id,
          relation: relation.relation,
          target_kind: relation.target.kind,
          target_id: relation.target.id,
          path: relation.relation_attributes.path,
          fragment: relation.relation_attributes.fragment,
          normalized_locator: relation.relation_attributes.normalized_locator
        )
        Success([
          fact(
            target_stream:,
            event:,
            markers: [
              "development-artifact:#{source_artifact_id}",
              "development-artifact-relation:#{relation.relation_id}",
              @marker_builder.relation_natural_key(relation)
            ],
            step_name: "declare-development-artifact-relation",
            source_event:
          )
        ])
      end

      def superseded(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        source_artifact_id:
      )
        declarations = [ source.superseded_relation_id, source.replacement_relation_id ].map do |relation_id|
          declaration = relation_declaration(
            source_event,
            relation_id:,
            source_artifact_id: source.source_artifact_id,
            source_upper_position:
          )
          allocation = allocate_relation(
            migration_id:,
            source_config_name:,
            declaration_event: declaration
          )
          return allocation if allocation.failure?

          allocation.value!.target_stream
        end
        superseded_stream, replacement_stream = declarations
        event = Events::DevelopmentArtifactRelationSupersededV2.new(
          relation_id: superseded_stream.stream_id,
          source_artifact_id:,
          replacement_relation_id: replacement_stream.stream_id,
          reason: source.reason
        )
        Success([
          fact(
            target_stream: superseded_stream,
            event:,
            markers: [
              "development-artifact:#{source_artifact_id}",
              "development-artifact-relation:#{superseded_stream.stream_id}",
              "development-artifact-relation:#{replacement_stream.stream_id}"
            ],
            step_name: "supersede-development-artifact-relation",
            source_event:
          )
        ])
      end

      def resolve_target(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_target:
      )
        if source_target.kind == "external"
          return Success(
            DevelopmentArtifacts::RelationTargetV1.new(
              kind: source_target.kind,
              id: source_target.id
            )
          )
        end

        resolved = resolve_entity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          kind: source_target.kind,
          source_id: source_target.id
        )
        return resolved if resolved.failure?

        Success(
          DevelopmentArtifacts::RelationTargetV1.new(
            kind: source_target.kind,
            id: resolved.value!
          )
        )
      end

      def resolve_entity(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        kind:,
        source_id:
      )
        target = TARGET_STREAMS.fetch(kind)
        allocation = @entity_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position: [ source_upper_position, source_event.global_position ].min,
          source_event:,
          source_stream: StreamReference.new(
            context: target.fetch(0),
            stream_name: target.fetch(1),
            stream_id: source_id
          ),
          target_stream_context: target.fetch(0),
          target_stream_name: target.fetch(1),
          identity_role: target.fetch(2)
        )
        return allocation if allocation.failure?

        Success(allocation.value!.target_stream.stream_id)
      end

      def allocate_relation(migration_id:, source_config_name:, declaration_event:)
        @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event: declaration_event,
          target_stream_context: "DevelopmentMemory",
          target_stream_name: "DevelopmentArtifactRelation",
          identity_role: "development-artifact-relation-#{declaration_event.stream_revision}"
        )
      end

      def relation_declaration(source_event, relation_id:, source_artifact_id:, source_upper_position:)
        stream = stream_for(source_event)
        event = @event_store.read_marked(
          stream,
          MarkedEventReadCriteria.new(
            event_type: "DevelopmentArtifactRelationDeclared",
            marker: "development-artifact-relation:#{relation_id}",
            maximum_count: 1,
            direction: :asc
          )
        ).first
        payload = event && load(event)
        relation = payload&.artifact_relation
        valid = event &&
                event.global_position <= source_upper_position &&
                event.global_position < source_event.global_position &&
                event.stream_revision < source_event.stream_revision &&
                payload.is_a?(LegacyEvents::DevelopmentArtifactRelationDeclaredV1) &&
                relation.relation_id == relation_id &&
                relation.source_artifact_id == source_artifact_id &&
                event.markers.include?("development-artifact:#{source_artifact_id}")
        raise ArgumentError, "relation declaration is absent or inconsistent" unless valid

        event
      end

      def validate_envelope!(source_event, source_payload, source_upper_position:)
        expected = SOURCE_TYPES.fetch(source_event.type)
        source_id = source_artifact_id(source_payload)
        valid = source_payload.is_a?(expected) &&
                source_event.metadata.fetch("schema_version") == expected.schema_version &&
                source_event.global_position <= source_upper_position &&
                source_event.stream.context == "DevelopmentMemory" &&
                source_event.stream.stream_name == "DevelopmentArtifact" &&
                source_event.stream.stream_id == source_id &&
                source_event.stream_revision.positive? &&
                source_event.markers.include?("development-artifact:#{source_id}")
        relation_ids(source_payload).each do |relation_id|
          valid &&= source_event.markers.include?("development-artifact-relation:#{relation_id}")
        end
        raise ArgumentError, "source identity, schema, stream, or markers are invalid" unless valid

        validate_artifact_root!(source_event, source_id, source_upper_position:)
      end

      def validate_artifact_root!(source_event, source_artifact_id, source_upper_position:)
        root = @event_store.read_at(stream_for(source_event), 0)
        payload = root && load(root)
        valid = root &&
                root.global_position <= source_upper_position &&
                payload.is_a?(LegacyEvents::DevelopmentArtifactCapturedV2) &&
                payload.artifact.artifact_id == source_artifact_id &&
                root.markers.include?("development-artifact:#{source_artifact_id}")
        raise ArgumentError, "captured Artifact source is absent or inconsistent" unless valid
      end

      def source_artifact_id(source)
        case source
        when LegacyEvents::DevelopmentArtifactRelationDeclaredV1
          source.artifact_relation.source_artifact_id
        when LegacyEvents::DevelopmentArtifactRelationSupersededV1
          source.source_artifact_id
        end
      end

      def relation_ids(source)
        case source
        when LegacyEvents::DevelopmentArtifactRelationDeclaredV1
          [ source.artifact_relation.relation_id ]
        when LegacyEvents::DevelopmentArtifactRelationSupersededV1
          [ source.superseded_relation_id, source.replacement_relation_id ]
        end
      end

      def fact(target_stream:, event:, markers:, step_name:, source_event:)
        TransformedFactV1.new(
          target_stream:,
          event:,
          markers:,
          step_name:,
          metadata_extension: MigrationMetadataExtensionV1.new(
            attributed_actor: Commands::Actor.new(
              kind: source_event.metadata.fetch("actor_kind"),
              id: source_event.metadata.fetch("actor_id")
            ),
            policy_version: source_event.metadata.fetch("policy_version")
          )
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
          message: "Development Artifact relation source is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
