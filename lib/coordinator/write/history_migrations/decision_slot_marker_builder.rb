# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class DecisionSlotMarkerBuilder
      def initialize(
        marker_component_builder: Coordinator::Shared::CanonicalMarkerComponentBuilder.new,
        compound_marker_builder: CompoundMarkerBuilder.new
      )
        @marker_component_builder = marker_component_builder
        @compound_marker_builder = compound_marker_builder
      end

      def call(document)
        @compound_marker_builder.call(
          CompoundMarkerDefinitionV1.new(
            purpose: "decision-slot",
            components: [
              "topic:#{document.topic_id}",
              "conflict-dimension:#{document.conflict_dimension}",
              "resolution-strategy:#{document.resolution_strategy}"
            ] +
              @marker_component_builder.call(dimension: "scope", value: document.exact_scope.to_h) +
              @marker_component_builder.call(dimension: "conditions", value: document.exact_conditions.to_h)
          )
        )
      end
    end
  end
end
