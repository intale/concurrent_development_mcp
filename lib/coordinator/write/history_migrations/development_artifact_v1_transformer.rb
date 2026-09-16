# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class DevelopmentArtifactV1Transformer
      include Dry::Monads[:result]

      def initialize(
        context_resolver:,
        target_plan_builder:,
        target_event_reference_resolver:,
        state_transition: DevelopmentArtifactStateTransition.new,
        marker_builder: DevelopmentArtifacts::MarkerBuilder.new
      )
        @context_resolver = context_resolver
        @target_plan_builder = target_plan_builder
        @target_event_reference_resolver = target_event_reference_resolver
        @state_transition = state_transition
        @marker_builder = marker_builder
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        resolved = @context_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_payload:
        )
        return resolved if resolved.failure?

        context = resolved.value!
        case source_payload
        when LegacyEvents::DevelopmentArtifactCapturedV2
          Success(capture_facts(context, source_event, source_payload.artifact))
        when LegacyEvents::DevelopmentArtifactObservedV1
          observed(
            migration_id:,
            source_upper_position:,
            source_event:,
            source: source_payload,
            context:
          )
        when LegacyEvents::DevelopmentArtifactClassificationCorrectedV1
          corrected(
            migration_id:,
            source_upper_position:,
            source_event:,
            source: source_payload,
            context:
          )
        end
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      private

      def capture_facts(context, source_event, artifact)
        facts = [
          artifact_fact(
            context,
            Events::DevelopmentArtifactCreatedV1.new(artifact_id: context.artifact_id),
            DevelopmentArtifactPropertySteps.created,
            source_event,
            markers: artifact_markers(context) + [ @marker_builder.natural_key(artifact) ]
          ),
          artifact_fact(
            context,
            Events::DevelopmentArtifactScopeChangedV1.new(
              artifact_id: context.artifact_id,
              scope: artifact.scope
            ),
            DevelopmentArtifactPropertySteps.property("scope", "initial"),
            source_event
          ),
          artifact_fact(
            context,
            Events::DevelopmentArtifactTitleChangedV1.new(
              artifact_id: context.artifact_id,
              title: artifact.title
            ),
            DevelopmentArtifactPropertySteps.property("title", "initial"),
            source_event
          ),
          artifact_fact(
            context,
            Events::DevelopmentArtifactKindChangedV1.new(
              artifact_id: context.artifact_id,
              kind: artifact.kind
            ),
            DevelopmentArtifactPropertySteps.property("kind", "initial"),
            source_event
          ),
          artifact_fact(
            context,
            Events::DevelopmentArtifactSourceChangedV1.new(
              artifact_id: context.artifact_id,
              source_kind: artifact.source.kind,
              locator: artifact.source.locator,
              revision: artifact.source.revision,
              observed_at: artifact.source.observed_at
            ),
            DevelopmentArtifactPropertySteps.property("source", "initial"),
            source_event,
            metadata_extension: source_metadata(source_event, artifact.source)
          ),
          artifact_fact(
            context,
            Events::DevelopmentArtifactContentChangedV1.new(
              artifact_id: context.artifact_id,
              content: content_representation(artifact.content)
            ),
            DevelopmentArtifactPropertySteps.content,
            source_event,
            metadata_extension: content_metadata(source_event, artifact.content)
          )
        ]
        artifact.labels.each_with_index do |label, index|
          facts << artifact_fact(
            context,
            Events::DevelopmentArtifactLabelAddedV1.new(
              artifact_id: context.artifact_id,
              label:
            ),
            DevelopmentArtifactPropertySteps.label_added("initial", index),
            source_event
          )
        end
        facts.freeze
      end

      def observed(migration_id:, source_upper_position:, source_event:, source:, context:)
        transition = @state_transition.call(
          state: context.state,
          source:,
          source_event:
        )
        property_facts = transition_facts(context, source_event, transition, source_kind: "observation")
        plans = preplan(migration_id:, source_event:, property_facts:)
        return plans if plans.failure?

        references = resolve_origins(
          migration_id:,
          source_upper_position:,
          source_event:,
          target_stream: context.artifact_stream,
          origins: observation_origins(transition.state)
        )
        return references if references.failure?

        observation_facts = [
          observation_recorded(context, source_event, transition.state.source)
        ]
        references.value!.each_with_index do |entry, index|
          origin, reference = entry
          observation_facts << observation_link(
            context,
            source_event,
            origin.role,
            reference,
            "link-development-artifact-observation-#{format('%02d', index + 1)}"
          )
        end
        Success((property_facts + observation_facts).freeze)
      end

      def corrected(migration_id:, source_upper_position:, source_event:, source:, context:)
        transition = @state_transition.call(
          state: context.state,
          source:,
          source_event:
        )
        property_facts = transition_facts(context, source_event, transition, source_kind: "classification")
        if property_facts.empty?
          return Failure(inconsistent(source_event, "classification correction contains no change"))
        end

        plans = preplan(migration_id:, source_event:, property_facts:)
        return plans if plans.failure?

        facts = property_facts + [
          observation_fact(
            context,
            Events::DevelopmentArtifactClassificationCorrectionRecordedV1.new(
              artifact_id: context.artifact_id,
              observation_id: context.observation_id,
              classification_revision: source.classification_revision,
              reason: source.reason
            ),
            "record-development-artifact-classification-correction",
            source_event
          )
        ]
        plans.value!.each_with_index do |plan, index|
          facts << observation_link(
            context,
            source_event,
            property_role(property_facts.fetch(index).event),
            plan.target_event,
            "link-development-artifact-classification-#{format('%02d', index + 1)}"
          )
        end
        Success(facts.freeze)
      end

      def transition_facts(context, source_event, transition, source_kind:)
        state = transition.state
        facts = []
        if transition.scope_changed
          facts << artifact_fact(
            context,
            Events::DevelopmentArtifactScopeChangedV1.new(
              artifact_id: context.artifact_id,
              scope: state.scope
            ),
            DevelopmentArtifactPropertySteps.property("scope", source_kind),
            source_event
          )
        end
        if transition.title_changed
          facts << artifact_fact(
            context,
            Events::DevelopmentArtifactTitleChangedV1.new(
              artifact_id: context.artifact_id,
              title: state.title
            ),
            DevelopmentArtifactPropertySteps.property("title", source_kind),
            source_event
          )
        end
        if transition.kind_changed
          facts << artifact_fact(
            context,
            Events::DevelopmentArtifactKindChangedV1.new(
              artifact_id: context.artifact_id,
              kind: state.kind
            ),
            DevelopmentArtifactPropertySteps.property("kind", source_kind),
            source_event
          )
        end
        if transition.source_changed
          facts << artifact_fact(
            context,
            Events::DevelopmentArtifactSourceChangedV1.new(
              artifact_id: context.artifact_id,
              source_kind: state.source.kind,
              locator: state.source.locator,
              revision: state.source.revision,
              observed_at: state.source.observed_at
            ),
            DevelopmentArtifactPropertySteps.property("source", source_kind),
            source_event,
            metadata_extension: source_metadata(source_event, state.source)
          )
        end
        transition.removed_labels.each_with_index do |label, index|
          facts << artifact_fact(
            context,
            Events::DevelopmentArtifactLabelRemovedV1.new(
              artifact_id: context.artifact_id,
              label:
            ),
            DevelopmentArtifactPropertySteps.label_removed(source_kind, index),
            source_event
          )
        end
        transition.added_labels.each_with_index do |label, index|
          facts << artifact_fact(
            context,
            Events::DevelopmentArtifactLabelAddedV1.new(
              artifact_id: context.artifact_id,
              label:
            ),
            DevelopmentArtifactPropertySteps.label_added(source_kind, index),
            source_event
          )
        end
        facts.freeze
      end

      def preplan(migration_id:, source_event:, property_facts:)
        return Success([]) if property_facts.empty?

        @target_plan_builder.call(
          migration_id:,
          source_event:,
          transformed_facts: property_facts
        )
      end

      def resolve_origins(
        migration_id:,
        source_upper_position:,
        source_event:,
        target_stream:,
        origins:
      )
        resolved = []
        origins.each do |origin|
          result = @target_event_reference_resolver.call_in_stream(
            migration_id:,
            source_upper_position:,
            source_event:,
            source_reference: origin.source_event,
            target_stream:,
            target_event_type: origin.event_type,
            target_step_name: origin.step_name
          )
          return result if result.failure?

          resolved << [ origin, result.value! ].freeze
        end
        Success(resolved.freeze)
      end

      def observation_origins(state)
        [
          state.created_origin,
          state.scope_origin,
          state.title_origin,
          state.kind_origin,
          state.source_origin,
          state.content_origin,
          *state.labels.sort_by { _1.label.b }.map(&:origin)
        ].freeze
      end

      def observation_recorded(context, source_event, source)
        observation_fact(
          context,
          Events::DevelopmentArtifactObservationRecordedV1.new(
            observation_id: context.observation_id
          ),
          "record-development-artifact-observation",
          source_event,
          metadata_extension: source_metadata(source_event, source)
        )
      end

      def observation_link(context, source_event, role, reference, step_name)
        observation_fact(
          context,
          Events::DevelopmentArtifactObservationFactLinkedV1.new(
            observation_id: context.observation_id,
            artifact_id: context.artifact_id,
            role:,
            observed_fact: reference
          ),
          step_name,
          source_event
        )
      end

      def artifact_fact(
        context,
        event,
        step_name,
        source_event,
        markers: artifact_markers(context),
        metadata_extension: actor_metadata(source_event)
      )
        fact(
          target_stream: context.artifact_stream,
          event:,
          markers:,
          step_name:,
          metadata_extension:
        )
      end

      def observation_fact(
        context,
        event,
        step_name,
        source_event,
        metadata_extension: actor_metadata(source_event)
      )
        fact(
          target_stream: context.observation_stream,
          event:,
          markers: observation_markers(context),
          step_name:,
          metadata_extension:
        )
      end

      def fact(target_stream:, event:, markers:, step_name:, metadata_extension:)
        TransformedFactV1.new(
          target_stream:,
          event:,
          markers:,
          step_name:,
          metadata_extension:
        )
      end

      def artifact_markers(context)
        [ "development-artifact:#{context.artifact_id}" ]
      end

      def observation_markers(context)
        [
          "development-artifact:#{context.artifact_id}",
          "development-artifact-observation:#{context.observation_id}"
        ]
      end

      def actor_metadata(source_event)
        MigrationMetadataExtensionV1.new(
          attributed_actor: actor_from(source_event),
          policy_version: source_event.metadata.fetch("policy_version")
        )
      end

      def source_metadata(source_event, source)
        MigrationMetadataExtensionV1.new(
          **actor_metadata(source_event).to_h,
          collector: source.collector
        )
      end

      def content_metadata(source_event, content)
        MigrationMetadataExtensionV1.new(
          **actor_metadata(source_event).to_h,
          encoding: content.encoding,
          media_type: content.media_type,
          byte_size: content.byte_size,
          content_sha256: content.content_sha256
        )
      end

      def actor_from(source_event)
        Commands::Actor.new(
          kind: source_event.metadata.fetch("actor_kind"),
          id: source_event.metadata.fetch("actor_id")
        )
      end

      def content_representation(content)
        content.respond_to?(:text) ? content.text : content.base64
      end

      def property_role(event)
        case event
        when Events::DevelopmentArtifactScopeChangedV1 then "scope"
        when Events::DevelopmentArtifactTitleChangedV1 then "title"
        when Events::DevelopmentArtifactKindChangedV1 then "kind"
        when Events::DevelopmentArtifactSourceChangedV1 then "source"
        when Events::DevelopmentArtifactLabelAddedV1,
             Events::DevelopmentArtifactLabelRemovedV1 then "label"
        else raise ArgumentError, "unsupported Development Artifact property fact #{event.class.name}"
        end
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
