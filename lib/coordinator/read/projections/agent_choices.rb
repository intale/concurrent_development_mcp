# frozen_string_literal: true

module Coordinator::Read::Projections
  class AgentChoices
    def initialize(patches:, invalidations: {})
      @patches, @invalidations = patches, invalidations
    end

    def apply(event)
      data = event.data
      id = data.fetch("choice_id")
      case event.type
      when "AgentChoiceRecorded"
        document = data.fetch("decision_context").fetch("document")
        digest = Coordinator::Shared::CanonicalJson.new.sha256(document)
        attributes = { choice_id: id, choice_type: data.fetch("choice_type"), selected: data.fetch("selected"),
          alternatives: data.fetch("alternatives"), reason_summary: data.fetch("reason_summary"), context: data.fetch("context"),
          context_digest: digest, decision_context: { document:, digest:, resolved_at: event.created_at.utc.iso8601(6) } }
          .merge(evidence(event, :recorded))
        @patches.insert(attributes.merge(observation_status: "recorded", created_at: event.created_at, updated_at: event.created_at))
        @patches.assign(attributes)
      when "AgentChoiceAccepted"
        @patches.assign({ choice_id: id, observation_status: "accepted", assessment: data.fetch("assessment") }.merge(evidence(event, :accepted)))
      when "AgentChoiceInvalidatedByDecision"
        source = @invalidations.fetch(event.id)
        @patches.assign({ choice_id: id, observation_status: "invalidated", invalidation: {
          assessment_event: Source.reference(source.fetch(:assessment_event)),
          decision_change_event: source.fetch(:decision_change).fetch(:source_event), reason: data.fetch("reason")
        } }.merge(evidence(event, :invalidated)))
      end
      @patches.touch({ choice_id: id }, time: event.created_at)
    end

    private

    def evidence(event, prefix)
      Source.evidence(event, prefix:).except(:"#{prefix}_global_position")
    end
  end
end
