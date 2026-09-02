# frozen_string_literal: true

module Coordinator::Write
  module AgentChoiceImpacts
    class AssessmentLoader
      def initialize(
        event_store:,
        schema_registry: EventSchemaRegistry.new,
        marker_builder: AssessmentMarkerBuilder.new,
        assessment_contract: Contracts::AgentChoiceImpactAssessment.new
      )
        @event_store = event_store
        @schema_registry = schema_registry
        @marker_builder = marker_builder
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
            event_types: [ "AgentChoiceImpactAssessed" ],
            markers: [ marker ],
            maximum_count: 2,
            direction: :asc
          )
        )
        if events.length > 1
          raise InvalidHistory.new(
            reason: "assessment_natural_key_duplicated",
            evidence: { marker:, event_ids: events.map(&:id) }
          )
        end
        event = events.first
        return unless event

        payload = @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
        valid = payload.is_a?(Events::AgentChoiceImpactAssessedV1) &&
                event.stream_revision == 0 &&
                payload.assessment_id == event.stream.stream_id &&
                payload.choice_id == command.choice_id &&
                payload.accepted_choice == command.accepted_choice &&
                payload.decision_change == command.decision_change &&
                payload.assessment.policy_version == command.policy_version
        assessment_validation = payload.is_a?(Events::AgentChoiceImpactAssessedV1) &&
                                @assessment_contract.call(assessment: payload.assessment)
        valid &&= assessment_validation && assessment_validation.success?
        unless valid
          raise InvalidHistory.new(
            reason: "assessment_replay_invalid",
            evidence: { assessment_id: event.stream.stream_id, event_id: event.id }
          )
        end

        event
      end
    end
  end
end
