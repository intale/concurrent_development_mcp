# frozen_string_literal: true

module Coordinator::Write
  module AgentChoiceImpacts
    class AssessmentMarkerBuilder
      def initialize(compound_marker_builder: CompoundMarkerBuilder.new)
        @compound_marker_builder = compound_marker_builder
      end

      def call(accepted_choice:, decision_change:)
        @compound_marker_builder.call(
          CompoundMarkerDefinitionV1.new(
            purpose: "agent-choice-impact-assessment",
            components: [
              "accepted-choice-event:#{accepted_choice.event_id}",
              "decision-change-event:#{decision_change.event_id}"
            ]
          )
        ).marker
      end
    end
  end
end
