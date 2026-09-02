# frozen_string_literal: true

module Coordinator::Write
  module Decisions
    class DecisionSlotBuilder
      EXCLUSIVE_STRATEGIES = %w[single_choice manual_resolution].freeze

      def initialize(
        id_generator: IdGenerator.new,
        marker_component_builder: Coordinator::Shared::CanonicalMarkerComponentBuilder.new,
        compound_marker_builder: CompoundMarkerBuilder.new
      )
        @id_generator = id_generator
        @marker_component_builder = marker_component_builder
        @compound_marker_builder = compound_marker_builder
      end

      def call(definition)
        document = definition.document
        topic = document.topic
        return unless EXCLUSIVE_STRATEGIES.include?(topic.resolution_strategy)

        slot_document = DecisionSlotDocumentV1.new(
          schema: "decision-slot/v1",
          topic_id: topic.topic_id,
          exact_scope: document.scope,
          exact_conditions: document.conditions,
          conflict_dimension: topic.conflict_dimension,
          resolution_strategy: topic.resolution_strategy
        )
        compound_marker = @compound_marker_builder.call(
          CompoundMarkerDefinitionV1.new(
            purpose: "decision-slot",
            components: [
              "topic:#{topic.topic_id}",
              "conflict-dimension:#{topic.conflict_dimension}",
              "resolution-strategy:#{topic.resolution_strategy}"
            ] +
              @marker_component_builder.call(dimension: "scope", value: document.scope.to_h) +
              @marker_component_builder.call(dimension: "conditions", value: document.conditions.to_h)
          )
        )

        DecisionSlotV1.new(
          slot_id: @id_generator.uuid_v7,
          document: slot_document,
          compound_marker:
        )
      end
    end
  end
end
