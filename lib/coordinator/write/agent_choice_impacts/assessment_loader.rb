# frozen_string_literal: true

module Coordinator::Write
  module AgentChoiceImpacts
    class AssessmentLoader
      def initialize(
        event_store:,
        stream_factory: StreamFactory.new,
        schema_registry: EventSchemaRegistry.new,
        assessment_contract: Contracts::AgentChoiceImpactAssessment.new
      )
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
        @assessment_contract = assessment_contract
      end

      def call(command)
        event = @event_store.read(
          @stream_factory.agent_choice_impact(command.assessment_id),
          EventQueries::AGENT_CHOICE_IMPACT_ASSESSMENT
        ).first
        return unless event

        payload = @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
        valid = payload.is_a?(Events::AgentChoiceImpactAssessedV1) &&
                event.stream_revision == 0 &&
                payload.assessment_id == command.assessment_id &&
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
            evidence: { assessment_id: command.assessment_id, event_id: event.id }
          )
        end

        event
      end
    end
  end
end
