# frozen_string_literal: true

module Coordinator::Read
  module AgentChoiceImpacts
    class AssessmentLoader
      EVENT_TYPES = %w[AgentChoiceImpactAssessmentRecorded AgentChoiceImpactSourceLinked].freeze

      def initialize(
        event_store:,
        stream_factory: Coordinator::Write::StreamFactory.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        decision_change_loader: DecisionChangeLoader.new(event_store:)
      )
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
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
        return if events.length < 3

        assessment_event = events.fetch(0)
        assessment = load_event(assessment_event)
        links = events.drop(1).map { load_event(_1) }
        accepted = links.find { _1.role == "accepted_choice" }
        decision = links.find { _1.role == "decision_change" }
        unless assessment.is_a?(Coordinator::Write::Events::AgentChoiceImpactAssessmentRecordedV1) &&
               assessment.assessment_id == assessment_id &&
               links.all? { _1.assessment_id == assessment_id } &&
               accepted && decision
          raise InvalidProjectionSource, "AgentChoice impact assessment facts are inconsistent"
        end

        decision_source = @decision_change_loader.call(decision.source)
        AssessmentViewV2.new(
          assessment_id:,
          choice_id: assessment.choice_id,
          attempt_id: assessment.attempt_id,
          assessment: assessment.assessment,
          accepted_choice: accepted.source,
          decision_change: decision_source.evidence,
          decision_changed_at: decision_source.changed_at,
          assessment_event:
        )
      rescue Dry::Struct::Error, KeyError => error
        raise InvalidProjectionSource, error.message
      end

      private

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end
    end
  end
end
