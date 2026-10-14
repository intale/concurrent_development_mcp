# frozen_string_literal: true

module Coordinator::Read
  module AgentChoiceImpacts
    class AssessmentLoader
      EVENT_TYPES = %w[AgentChoiceImpactAssessmentRecorded AgentChoiceImpactSourceLinked].freeze

      def initialize(
        event_store:,
        stream_factory: Coordinator::Write::StreamFactory.new,
        decision_change_loader: DecisionChangeLoader.new(event_store:)
      )
        @event_store = event_store
        @stream_factory = stream_factory
        @decision_change_loader = decision_change_loader
      end

      def call(assessment_id)
        events = @event_store.read(
          @stream_factory.agent_choice_impact(assessment_id),
          Coordinator::Write::EventReadCriteria.new(
            event_types: EVENT_TYPES,
            maximum_count: 3,
            direction: :asc
          )
        )
        assessment_event = events.fetch(0)
        assessment = CommandResults::Source.document(assessment_event.data)
        links = events.drop(1).map { CommandResults::Source.document(_1.data) }
        accepted = links.find { _1.fetch(:role) == "accepted_choice" }
        decision = links.find { _1.fetch(:role) == "decision_change" }
        decision_source = @decision_change_loader.call(decision.fetch(:source))
        {
          assessment_id:,
          choice_id: assessment.fetch(:choice_id),
          attempt_id: assessment.fetch(:attempt_id),
          assessment: assessment.fetch(:assessment),
          accepted_choice: accepted.fetch(:source),
          decision_change: decision_source.fetch(:evidence),
          decision_changed_at: decision_source.fetch(:changed_at),
          assessment_event:
        }
      end
    end
  end
end
