# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class MarkerBuilder
      NATURAL_KEY_PURPOSE = "development-artifact-natural-key"
      RELATION_NATURAL_KEY_PURPOSE = "development-artifact-relation-natural-key"

      def initialize(
        marker_codec: Coordinator::Shared::Markers::CodecV2.new,
        marker_component_builder: Coordinator::Shared::CanonicalMarkerComponentBuilder.new,
        compound_marker_builder: CompoundMarkerBuilder.new
      )
        @marker_codec = marker_codec
        @marker_component_builder = marker_component_builder
        @compound_marker_builder = compound_marker_builder
      end

      def capture(event:, command_id:)
        markers = [ "command:#{command_id}" ]
        case event
        when Events::DevelopmentArtifactCapturedV2
          markers << "development-artifact:#{event.artifact.artifact_id}"
          markers << natural_key(event.artifact)
        when Events::DevelopmentArtifactObservedV1
          markers << "development-artifact:#{event.observation.artifact_id}"
          markers << "development-artifact-observation:#{event.observation.observation_id}"
        when Events::DevelopmentArtifactCreatedV1
          markers << "development-artifact:#{event.artifact_id}"
        else
          raise "Unexpected Development Artifact capture event #{event.class.name}"
        end
        markers.freeze
      end

      def artifact(event:, command_id:, natural_key: nil)
        markers = [ "development-artifact:#{event.artifact_id}", "command:#{command_id}" ]
        markers << natural_key if natural_key
        markers.freeze
      end

      def observation(event:, command_id:)
        [
          "development-artifact-observation:#{event.observation_id}",
          "command:#{command_id}"
        ].freeze
      end

      def natural_key(artifact)
        result = @marker_codec.call(
          purpose: NATURAL_KEY_PURPOSE,
          components: [
            { dimension: "scope", value: artifact.scope },
            { dimension: "source-kind", value: artifact.source.kind },
            { dimension: "source-locator", value: artifact.source.locator }
          ]
        )
        if result.failure?
          raise ArgumentError, "Development Artifact natural key is invalid: #{result.failure.errors.inspect}"
        end

        result.value!.marker
      end


      def classification(event:, command_id:)
        [
          "development-artifact:#{event.artifact_id}",
          "development-artifact-observation:#{event.observation_id}",
          "command:#{command_id}"
        ].freeze
      end

      def relation(artifact_relation:, command_id:)
        [
          "development-artifact:#{artifact_relation.source_artifact_id}",
          "development-artifact-relation:#{artifact_relation.relation_id}",
          relation_natural_key(artifact_relation),
          "command:#{command_id}"
        ].freeze
      end

      def relation_v2(artifact_relation:, command_id:)
        [
          "development-artifact:#{artifact_relation.source_artifact_id}",
          "development-artifact-relation:#{artifact_relation.relation_id}",
          relation_natural_key(artifact_relation),
          "command:#{command_id}"
        ].freeze
      end

      def relation_natural_key(artifact_relation)
        target = artifact_relation.target
        components = [
          "source-artifact-id:#{artifact_relation.source_artifact_id}",
          "relation:#{artifact_relation.relation}"
        ]
        # Verification metadata (status, name and scope) is projection-time
        # context, not relation identity. Only the stable target tuple belongs
        # in the natural-key marker.
        components.concat(
          @marker_component_builder.call(
            dimension: "target",
            value: { kind: target.kind, id: target.id }
          )
        )
        components.concat(
          @marker_component_builder.call(
            dimension: "attributes",
            value: artifact_relation.relation_attributes.to_h
          )
        )
        @compound_marker_builder.call(
          CompoundMarkerDefinitionV1.new(
            purpose: RELATION_NATURAL_KEY_PURPOSE,
            components:
          )
        ).marker
      end

      def supersession(event:, command_id:)
        markers = [
          "development-artifact:#{event.source_artifact_id}",
          "development-artifact-relation:#{event.respond_to?(:superseded_relation_id) ? event.superseded_relation_id : event.relation_id}",
          "command:#{command_id}"
        ]
        markers.insert(2, "development-artifact-relation:#{event.replacement_relation_id}") if event.replacement_relation_id
        markers.freeze
      end
    end
  end
end
