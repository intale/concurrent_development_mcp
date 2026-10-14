# frozen_string_literal: true

module Coordinator::Read::Projections
  class AgentChoiceImpacts
    def initialize(patches:, sources:)
      @patches, @sources = patches, sources
    end

    def apply(event)
      id = event.data.fetch("assessment_id")
      source = @sources.fetch(id)
      recorded = source.fetch(:assessment_event)
      @patches.insert(creation(source).merge(created_at: recorded.created_at, updated_at: event.created_at))
      case event.type
      when "AgentChoiceImpactAssessmentRecorded"
        @patches.assign(assessment_attributes(source))
      when "AgentChoiceImpactSourceLinked"
        reference = Coordinator::Read::CommandResults::Source.document(event.data.fetch("source"))
        if event.data.fetch("role") == "accepted_choice"
          @patches.assign(assessment_id: id, accepted_choice: reference)
        else
          change = source.fetch(:decision_change)
          @patches.assign(assessment_id: id, decision_change: change.merge(changed_at: source.fetch(:decision_changed_at)),
            source_actor: change.fetch(:source_actor).merge(authenticated: false))
        end
      end
      @patches.touch({ assessment_id: id }, time: event.created_at)
    end

    private

    def creation(source)
      change = source.fetch(:decision_change)
      assessment_attributes(source).merge(accepted_choice: source.fetch(:accepted_choice),
        decision_change: change.merge(changed_at: source.fetch(:decision_changed_at)),
        source_actor: change.fetch(:source_actor).merge(authenticated: false))
    end

    def assessment_attributes(source)
      event = source.fetch(:assessment_event)
      assessment = source.fetch(:assessment)
      { assessment_id: source.fetch(:assessment_id), choice_id: source.fetch(:choice_id), attempt_id: source.fetch(:attempt_id),
        outcome: assessment.fetch(:outcome), reason: assessment.fetch(:reason), assessment:,
        policy_version: event.metadata.fetch("policy_version"), assessment_event: Source.reference(event),
        assessment_actor: Source.actor(event), markers: event.markers, metadata: event.metadata,
        causation_id: event.causation_id, correlation_id: event.correlation_id, event_global_position: event.global_position,
        assessed_at_domain: event.created_at, assessed_at_store: event.created_at }
    end
  end
end
