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
        accepted = links.find do
          _1.is_a?(Coordinator::Write::Events::AgentChoiceImpactSourceLinkedV1) &&
            _1.role == "accepted_choice"
        end
        decision = links.find do
          _1.is_a?(Coordinator::Write::Events::AgentChoiceImpactSourceLinkedV1) &&
            _1.role == "decision_change"
        end
        before_digest = assessment_event.metadata["before_context_digest"]
        after_digest = assessment_event.metadata["after_context_digest"]
        valid_links = links.all? do
          _1.is_a?(Coordinator::Write::Events::AgentChoiceImpactSourceLinkedV1) &&
            _1.assessment_id == assessment_id
        end
        unless assessment.is_a?(Coordinator::Write::Events::AgentChoiceImpactAssessmentRecordedV1) &&
               assessment.assessment_id == assessment_id &&
               events.map(&:stream_revision) == [ 0, 1, 2 ] &&
               valid_links &&
               accepted && valid_accepted_source?(accepted.source) &&
               decision && valid_decision_source?(decision.source) &&
               Coordinator::Write::Types::SHA256_DIGEST_PATTERN.match?(before_digest.to_s) &&
               Coordinator::Write::Types::SHA256_DIGEST_PATTERN.match?(after_digest.to_s) &&
               before_digest != after_digest
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

      def valid_accepted_source?(source)
        source.type == "AgentChoiceAccepted" &&
          source.stream_context == "AgentGovernance" &&
          source.stream_name == "AgentChoice" &&
          source.stream_revision == 1
      end

      def valid_decision_source?(source)
        %w[DecisionActivated DecisionDefinitionCorrected].include?(source.type) &&
          source.stream_context == "HumanGuidance" &&
          source.stream_name == "Decision"
      end
    end
  end
end
