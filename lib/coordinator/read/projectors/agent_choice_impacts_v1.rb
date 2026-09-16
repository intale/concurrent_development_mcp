# frozen_string_literal: true

module Coordinator::Read
  module Projectors
    class AgentChoiceImpactsV1
      PROJECTION = ProjectionDefinition.new(name: "agent_choice_impacts", version: 1)

      def initialize(
        assessment_loader:,
        contract: Contracts::AgentChoiceImpactSourceEvent.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        impacts: Repositories::AgentChoiceImpacts.new,
        choices: Repositories::AgentChoices.new,
        processed_events: Repositories::ProcessedProjectionEvents.new
      )
        @contract = contract
        @assessment_loader = assessment_loader
        @schema_registry = schema_registry
        @impacts = impacts
        @choices = choices
        @processed_events = processed_events
      end

      def call(event)
        payload = load_payload(event)
        verify_stream_identity!(event, payload)
        identity = ProjectionEventIdentity.from_event(event)

        ApplicationRecord.transaction do
          next unless @processed_events.claim(
            definition: PROJECTION,
            identity:,
            processed_at: event.created_at
          )

          project(event, payload)
        end

        nil
      end

      private

      def load_payload(event)
        result = @contract.call(
          event_type: event.type,
          schema_version: event.metadata["schema_version"],
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision,
          global_position: event.global_position,
          command_id: event.metadata["command_id"],
          actor_kind: event.metadata["actor_kind"],
          actor_id: event.metadata["actor_id"],
          recorded_by: event.metadata["recorded_by"],
          policy_version: event.metadata["policy_version"],
          before_context_digest: event.metadata["before_context_digest"],
          after_context_digest: event.metadata["after_context_digest"],
          previous_context_digest: event.metadata["previous_context_digest"],
          resulting_context_digest: event.metadata["resulting_context_digest"]
        )
        raise InvalidProjectionSource, result.errors.to_h.inspect if result.failure?

        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def verify_stream_identity!(event, payload)
        expected =
          case payload
          when Coordinator::Write::Events::AgentChoiceImpactAssessmentRecordedV1,
               Coordinator::Write::Events::AgentChoiceImpactSourceLinkedV1
            payload.assessment_id
          when Coordinator::Write::Events::AgentChoiceInvalidatedByDecisionV2
            payload.choice_id
          end
        return if event.stream.stream_id == expected

        raise InvalidProjectionSource, "AgentChoice impact identity does not match its source stream"
      end

      def project(event, payload)
        case payload
        when Coordinator::Write::Events::AgentChoiceImpactAssessmentRecordedV1
          true
        when Coordinator::Write::Events::AgentChoiceImpactSourceLinkedV1
          return unless event.stream_revision == 2

          assessment = @assessment_loader.call(payload.assessment_id)
          raise InvalidProjectionSource, "AgentChoice impact assessment is incomplete" unless assessment

          @impacts.store_assessment(
            event: assessment.assessment_event,
            projection_event: event,
            impact: assessment
          )
        when Coordinator::Write::Events::AgentChoiceInvalidatedByDecisionV2
          assessment = @assessment_loader.call(assessment_id(event))
          raise InvalidProjectionSource, "AgentChoice invalidation assessment is incomplete" unless assessment

          @choices.invalidate(event:, invalidation: payload, assessment:)
        end
      end

      def assessment_id(event)
        marker = event.markers.find { _1.start_with?("impact-assessment:") }
        raise InvalidProjectionSource, "AgentChoice invalidation has no assessment marker" unless marker

        marker.delete_prefix("impact-assessment:")
      end
    end
  end
end
