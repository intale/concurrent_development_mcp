# frozen_string_literal: true

module Coordinator::Write
  module AgentChoiceImpacts
    class AssessmentLoader
      def initialize(
        event_store:,
        schema_registry: EventSchemaRegistry.new,
        marker_builder: AssessmentMarkerBuilder.new,
        stream_factory: StreamFactory.new,
        assessment_contract: Contracts::AgentChoiceImpactAssessment.new
      )
        @event_store = event_store
        @schema_registry = schema_registry
        @marker_builder = marker_builder
        @stream_factory = stream_factory
        @assessment_contract = assessment_contract
      end

      def call(command)
        marker = @marker_builder.call(
          accepted_choice: command.accepted_choice,
          decision_change: command.decision_change.source_event
        )
        events = @event_store.read_global_marked(
          GlobalMarkedEventReadCriteria.new(
            stream_context: "AgentGovernance",
            stream_name: "AgentChoiceImpact",
            event_types: [ "AgentChoiceImpactAssessed", "AgentChoiceImpactAssessmentRecorded" ],
            markers: [ marker ],
            maximum_count: 2,
            direction: :asc
          )
        )
        duplicate!(marker, events) if events.length > 1
        event = events.first
        return unless event

        payload = load(event)
        valid = case payload
                when Events::AgentChoiceImpactAssessedV1
                  valid_legacy?(event, payload, command)
                when Events::AgentChoiceImpactAssessmentRecordedV1
                  valid_current?(event, payload, command)
                else
                  false
                end
        replay_invalid!(event) unless valid
        event
      end

      private

      def valid_legacy?(event, payload, command)
        validation = @assessment_contract.call(assessment: payload.assessment)
        event.stream_revision == 0 &&
          payload.assessment_id == event.stream.stream_id &&
          payload.choice_id == command.choice_id &&
          payload.accepted_choice == command.accepted_choice &&
          payload.decision_change == command.decision_change &&
          payload.assessment.policy_version == command.policy_version &&
          validation.success?
      end

      def valid_current?(event, payload, command)
        events = @event_store.read(
          @stream_factory.agent_choice_impact(payload.assessment_id),
          EventReadCriteria.new(
            event_types: [ "AgentChoiceImpactAssessmentRecorded", "AgentChoiceImpactSourceLinked" ],
            maximum_count: 3,
            direction: :asc
          )
        )
        links = events.drop(1).map { load(_1) }
        event.stream_revision == 0 &&
          payload.assessment_id == event.stream.stream_id &&
          payload.choice_id == command.choice_id &&
          event.metadata.fetch("policy_version") == command.policy_version &&
          links.length == 2 &&
          links.any? { _1.role == "accepted_choice" && _1.source == command.accepted_choice } &&
          links.any? do
            _1.role == "decision_change" &&
              _1.source == command.decision_change.source_event
          end
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def duplicate!(marker, events)
        raise InvalidHistory.new(
          reason: "assessment_natural_key_duplicated",
          evidence: { marker:, event_ids: events.map(&:id) }
        )
      end

      def replay_invalid!(event)
        raise InvalidHistory.new(
          reason: "assessment_replay_invalid",
          evidence: { assessment_id: event.stream.stream_id, event_id: event.id }
        )
      end
    end
  end
end
