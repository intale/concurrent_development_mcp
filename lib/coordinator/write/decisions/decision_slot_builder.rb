# frozen_string_literal: true

module Coordinator::Write
  module Decisions
    class DecisionSlotBuilder
      EXCLUSIVE_STRATEGIES = %w[single_choice manual_resolution].freeze

      def initialize(
        canonical_json: CanonicalJson.new,
        compound_marker_builder: CompoundMarkerBuilder.new
      )
        @canonical_json = canonical_json
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
        scope_digest = @canonical_json.sha256(document.scope.to_h)
        conditions_digest = @canonical_json.sha256(document.conditions.to_h)
        compound_marker = @compound_marker_builder.call(
          CompoundMarkerDefinitionV1.new(
            purpose: "decision-slot",
            components: [
              "topic:#{topic.topic_id}",
              "scope:v1:#{scope_digest}",
              "conditions:v1:#{conditions_digest}",
              "conflict-dimension:#{topic.conflict_dimension}",
              "resolution-strategy:#{topic.resolution_strategy}"
            ]
          )
        )

        DecisionSlotV1.new(
          slot_id: compound_marker.marker,
          document: slot_document,
          compound_marker:
        )
      end
    end
  end
end
