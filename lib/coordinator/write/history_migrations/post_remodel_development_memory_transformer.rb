# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class PostRemodelDevelopmentMemoryTransformer
      include Dry::Monads[:result]

      ARTIFACT_EVENTS = [
        Events::DevelopmentArtifactContentChangedV1,
        Events::DevelopmentArtifactCreatedV1,
        Events::DevelopmentArtifactKindChangedV1,
        Events::DevelopmentArtifactLabelAddedV1,
        Events::DevelopmentArtifactScopeChangedV1,
        Events::DevelopmentArtifactSourceChangedV1,
        Events::DevelopmentArtifactTitleChangedV1
      ].freeze
      ARTIFACT_REFERENCE_STEPS = {
        "DevelopmentArtifactContentChanged" => "change-development-artifact-content",
        "DevelopmentArtifactCreated" => "create-development-artifact",
        "DevelopmentArtifactKindChanged" => "change-development-artifact-kind",
        "DevelopmentArtifactLabelAdded" => "add-development-artifact-label",
        "DevelopmentArtifactScopeChanged" => "change-development-artifact-scope",
        "DevelopmentArtifactSourceChanged" => "change-development-artifact-source",
        "DevelopmentArtifactTitleChanged" => "change-development-artifact-title"
      }.freeze
      RELATION_TARGETS = {
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
      GUIDANCE_TARGETS = {
        "repository" => [ "DevelopmentPlanning", "Repository", "repository" ],
        "change_set" => [ "DevelopmentPlanning", "ChangeSet", "change-set" ],
        "work_item" => [ "DevelopmentExecution", "WorkItem", "work-item" ],
        "attempt" => [ "DevelopmentExecution", "Attempt", "attempt" ]
      }.freeze

      def initialize(
        event_store:,
        stream_identity_allocator:,
        entity_reference_resolver:,
        target_event_reference_resolver:,
        guidance_identity_resolver:,
        marker_builder: DevelopmentArtifacts::MarkerBuilder.new,
        schema_registry: EventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_identity_allocator = stream_identity_allocator
        @entity_reference_resolver = entity_reference_resolver
        @target_event_reference_resolver = target_event_reference_resolver
        @guidance_identity_resolver = guidance_identity_resolver
        @marker_builder = marker_builder
        @schema_registry = schema_registry
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        case source_payload
        when *ARTIFACT_EVENTS
          artifact_fact(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload
          )
        when Events::DevelopmentArtifactObservationRecordedV1
          observation_recorded(
            migration_id:,
            source_config_name:,
            source_event:,
            source: source_payload
          )
        when Events::DevelopmentArtifactObservationFactLinkedV1
          observation_linked(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload
          )
        when Events::DevelopmentArtifactRelationDeclaredV2
          relation_declared(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload
          )
        when Events::UserUtteranceForwardedByAgentV2
          guidance_message(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload
          )
        when Events::GuidanceMessageAnchoredV1
          guidance_anchor(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload
          )
        end
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error,
             EventHistoryLimitExceeded => error
        Failure(invalid(source_event, error.message))
      end

      private

      def artifact_fact(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:
      )
        artifact = allocate(
          migration_id:,
          source_config_name:,
          source_event:,
          context: "DevelopmentMemory",
          stream_name: "DevelopmentArtifact",
          identity_role: "development-artifact"
        )
        return artifact if artifact.failure?

        target_stream = artifact.value!.target_stream
        artifact_id = target_stream.stream_id
        target = target_artifact_event(source, artifact_id:)
        markers = [ "development-artifact:#{artifact_id}" ]
        if source.is_a?(Events::DevelopmentArtifactCreatedV1)
          natural_key = artifact_natural_key(source_event, source_upper_position:)
          markers << @marker_builder.natural_key(natural_key)
        end
        Success([
          fact(
            target_stream:,
            event: target,
            markers:,
            step_name: ARTIFACT_REFERENCE_STEPS.fetch(source.class.event_type),
            source_event:,
            metadata_extension: artifact_metadata(source_event, source:)
          )
        ])
      end

      def observation_recorded(migration_id:, source_config_name:, source_event:, source:)
        observation = allocate(
          migration_id:,
          source_config_name:,
          source_event:,
          context: "DevelopmentMemory",
          stream_name: "DevelopmentArtifactObservation",
          identity_role: "development-artifact-observation"
        )
        return observation if observation.failure?

        target_stream = observation.value!.target_stream
        observation_id = target_stream.stream_id
        Success([
          fact(
            target_stream:,
            event: Events::DevelopmentArtifactObservationRecordedV1.new(observation_id:),
            markers: [ "development-artifact-observation:#{observation_id}" ],
            step_name: "record-development-artifact-observation",
            source_event:,
            metadata_extension: metadata(source_event)
          )
        ])
      end

      def observation_linked(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:
      )
        observation = allocate(
          migration_id:,
          source_config_name:,
          source_event:,
          context: "DevelopmentMemory",
          stream_name: "DevelopmentArtifactObservation",
          identity_role: "development-artifact-observation"
        )
        return observation if observation.failure?

        artifact = resolve_entity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_context: "DevelopmentMemory",
          source_name: "DevelopmentArtifact",
          source_id: source.artifact_id,
          target_context: "DevelopmentMemory",
          target_name: "DevelopmentArtifact",
          identity_role: "development-artifact"
        )
        return artifact if artifact.failure?

        target_artifact_stream = artifact.value!.target_stream
        target_reference = @target_event_reference_resolver.call_in_stream(
          migration_id:,
          source_upper_position:,
          source_event:,
          source_reference: source.observed_fact,
          target_stream: target_artifact_stream,
          target_event_type: source.observed_fact.type,
          target_step_name: ARTIFACT_REFERENCE_STEPS.fetch(source.observed_fact.type)
        )
        return target_reference if target_reference.failure?

        target_stream = observation.value!.target_stream
        observation_id = target_stream.stream_id
        Success([
          fact(
            target_stream:,
            event: Events::DevelopmentArtifactObservationFactLinkedV1.new(
              observation_id:,
              artifact_id: target_artifact_stream.stream_id,
              role: source.role,
              observed_fact: target_reference.value!
            ),
            markers: [ "development-artifact-observation:#{observation_id}" ],
            step_name: "link-development-artifact-observation-fact",
            source_event:,
            metadata_extension: metadata(source_event)
          )
        ])
      end

      def relation_declared(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:
      )
        relation = allocate(
          migration_id:,
          source_config_name:,
          source_event:,
          context: "DevelopmentMemory",
          stream_name: "DevelopmentArtifactRelation",
          identity_role: "development-artifact-relation"
        )
        return relation if relation.failure?

        source_artifact = resolve_relation_target(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          kind: "artifact",
          source_id: source.source_artifact_id
        )
        return source_artifact if source_artifact.failure?

        target = if source.target_kind == "external"
          Success(source.target_id)
        else
          resolve_relation_target(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            kind: source.target_kind,
            source_id: source.target_id
          )
        end
        return target if target.failure?

        target_stream = relation.value!.target_stream
        relation_id = target_stream.stream_id
        source_artifact_id = source_artifact.value!
        target_relation = DevelopmentArtifacts::RelationV1.new(
          relation_id:,
          source_artifact_id:,
          relation: source.relation,
          target: DevelopmentArtifacts::RelationTargetV1.new(
            kind: source.target_kind,
            id: target.value!
          ),
          attributes: DevelopmentArtifacts::RelationAttributesV1.new(
            path: source.path,
            fragment: source.fragment,
            normalized_locator: source.normalized_locator
          )
        )
        event = Events::DevelopmentArtifactRelationDeclaredV2.new(
          relation_id:,
          source_artifact_id:,
          relation: target_relation.relation,
          target_kind: target_relation.target.kind,
          target_id: target_relation.target.id,
          path: target_relation.relation_attributes.path,
          fragment: target_relation.relation_attributes.fragment,
          normalized_locator: target_relation.relation_attributes.normalized_locator
        )
        Success([
          fact(
            target_stream:,
            event:,
            markers: [
              "development-artifact:#{source_artifact_id}",
              "development-artifact-relation:#{relation_id}",
              @marker_builder.relation_natural_key(target_relation)
            ],
            step_name: "declare-development-artifact-relation",
            source_event:,
            metadata_extension: metadata(source_event)
          )
        ])
      end

      def guidance_message(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:
      )
        guidance = @guidance_identity_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_conversation_id: source.conversation_id,
          source_message_id: source.message_id
        )
        return guidance if guidance.failure?

        conversation_stream = guidance.value!.target_stream
        message_id = guidance.value!.message_id
        conversation_id = conversation_stream.stream_id
        Success([
          fact(
            target_stream: conversation_stream,
            event: Events::UserUtteranceForwardedByAgentV2.new(
              conversation_id:,
              message_id:,
              source: source.source,
              text: source.text
            ),
            markers: [ "conversation:#{conversation_id}", "message:#{message_id}" ],
            step_name: "forward-user-utterance",
            source_event:,
            metadata_extension: metadata(source_event)
          )
        ])
      end

      def guidance_anchor(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:
      )
        guidance = @guidance_identity_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_conversation_id: source.conversation_id,
          source_message_id: source.message_id
        )
        return guidance if guidance.failure?

        target = GUIDANCE_TARGETS.fetch(source.anchor_kind)
        anchor = resolve_entity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_context: target.fetch(0),
          source_name: target.fetch(1),
          source_id: source.anchor_id,
          target_context: target.fetch(0),
          target_name: target.fetch(1),
          identity_role: target.fetch(2)
        )
        return anchor if anchor.failure?

        conversation_stream = guidance.value!.target_stream
        message_id = guidance.value!.message_id
        conversation_id = conversation_stream.stream_id
        anchor_id = anchor.value!.target_stream.stream_id
        Success([
          fact(
            target_stream: conversation_stream,
            event: Events::GuidanceMessageAnchoredV1.new(
              conversation_id:,
              message_id:,
              anchor_kind: source.anchor_kind,
              anchor_id:
            ),
            markers: [
              "conversation:#{conversation_id}",
              "message:#{message_id}",
              "#{source.anchor_kind.tr('_', '-')}:#{anchor_id}"
            ],
            step_name: "anchor-guidance-message-#{source.anchor_kind}",
            source_event:,
            metadata_extension: metadata(source_event)
          )
        ])
      end

      def target_artifact_event(source, artifact_id:)
        case source
        when Events::DevelopmentArtifactCreatedV1
          Events::DevelopmentArtifactCreatedV1.new(artifact_id:)
        when Events::DevelopmentArtifactScopeChangedV1
          Events::DevelopmentArtifactScopeChangedV1.new(artifact_id:, scope: source.scope)
        when Events::DevelopmentArtifactTitleChangedV1
          Events::DevelopmentArtifactTitleChangedV1.new(artifact_id:, title: source.title)
        when Events::DevelopmentArtifactKindChangedV1
          Events::DevelopmentArtifactKindChangedV1.new(artifact_id:, kind: source.kind)
        when Events::DevelopmentArtifactLabelAddedV1
          Events::DevelopmentArtifactLabelAddedV1.new(artifact_id:, label: source.label)
        when Events::DevelopmentArtifactSourceChangedV1
          Events::DevelopmentArtifactSourceChangedV1.new(
            artifact_id:,
            source_kind: source.source_kind,
            locator: source.locator,
            revision: source.revision,
            observed_at: source.observed_at
          )
        when Events::DevelopmentArtifactContentChangedV1
          Events::DevelopmentArtifactContentChangedV1.new(
            artifact_id:,
            content: source.content
          )
        end
      end

      def artifact_natural_key(source_event, source_upper_position:)
        events = @event_store.read(
          stream_for(source_event),
          EventReadCriteria.new(
            event_types: [
              "DevelopmentArtifactCreated",
              "DevelopmentArtifactScopeChanged",
              "DevelopmentArtifactSourceChanged"
            ],
            maximum_count: Types::DEVELOPMENT_ARTIFACT_HISTORY_MAXIMUM_COUNT,
            direction: :asc
          )
        ).select { _1.global_position <= source_upper_position }
        created = events.find { _1.type == "DevelopmentArtifactCreated" }
        scope_event = events.find { _1.type == "DevelopmentArtifactScopeChanged" }
        source_change_event = events.find { _1.type == "DevelopmentArtifactSourceChanged" }
        scope = scope_event && load(scope_event)
        source = source_change_event && load(source_change_event)
        valid = created&.id == source_event.id &&
                scope.is_a?(Events::DevelopmentArtifactScopeChangedV1) &&
                source.is_a?(Events::DevelopmentArtifactSourceChangedV1)
        raise ArgumentError, "Artifact initial scope/source facts are absent" unless valid

        DevelopmentArtifacts::NaturalKeyV1.new(
          scope: scope.scope,
          source: DevelopmentArtifacts::SourceV1.new(
            kind: source.source_kind,
            locator: source.locator,
            revision: source.revision,
            observed_at: source.observed_at,
            collector: source_change_event.metadata.fetch("collector")
          )
        )
      end

      def artifact_metadata(source_event, source:)
        attributes = {}
        case source
        when Events::DevelopmentArtifactContentChangedV1
          attributes = {
            encoding: source_event.metadata.fetch("encoding"),
            media_type: source_event.metadata.fetch("media_type"),
            byte_size: source_event.metadata.fetch("byte_size"),
            content_sha256: source_event.metadata.fetch("content_sha256")
          }
        when Events::DevelopmentArtifactSourceChangedV1
          attributes = { collector: source_event.metadata.fetch("collector") }
        end
        metadata(source_event, **attributes)
      end

      def resolve_relation_target(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        kind:,
        source_id:
      )
        target = RELATION_TARGETS.fetch(kind)
        resolve_entity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_context: target.fetch(0),
          source_name: target.fetch(1),
          source_id:,
          target_context: target.fetch(0),
          target_name: target.fetch(1),
          identity_role: target.fetch(2)
        ).fmap { _1.target_stream.stream_id }
      end

      def allocate(
        migration_id:,
        source_config_name:,
        source_event:,
        context:,
        stream_name:,
        identity_role:
      )
        @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_context: context,
          target_stream_name: stream_name,
          identity_role:
        )
      end

      def resolve_entity(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_context:,
        source_name:,
        source_id:,
        target_context:,
        target_name:,
        identity_role:
      )
        @entity_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_stream: StreamReference.new(
            context: source_context,
            stream_name: source_name,
            stream_id: source_id
          ),
          target_stream_context: target_context,
          target_stream_name: target_name,
          identity_role:
        )
      end

      def metadata(source_event, **attributes)
        MigrationMetadataExtensionV1.new(
          attributed_actor: Commands::Actor.new(
            kind: source_event.metadata.fetch("actor_kind"),
            id: source_event.metadata.fetch("actor_id")
          ),
          policy_version: source_event.metadata["policy_version"],
          **attributes
        )
      end

      def fact(target_stream:, event:, markers:, step_name:, source_event:, metadata_extension:)
        TransformedFactV1.new(
          target_stream:,
          event:,
          markers:,
          step_name:,
          metadata_extension:
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

      def invalid(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Post-remodel Development Memory transformation is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
