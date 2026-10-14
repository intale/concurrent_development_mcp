# frozen_string_literal: true

module Coordinator::Read::Projections
  class DecisionInterpretations
    def initialize(patches:, sources:, assessments: {})
      @patches, @sources, @assessments = patches, sources, assessments
    end

    def apply(event)
      data = event.data
      id = data.fetch("interpretation_id")
      case event.type
      when "DecisionInterpretationProposed" then propose(event, data)
      when "DecisionClarificationRequired" then clarify(event, data)
      when "DecisionInterpretationAccepted"
        adjudicate(event, data, action: "accept", outcome: "accepted_for_activation", code: "accepted", slot: data.fetch("slot"))
      when "DecisionInterpretationRejected"
        adjudicate(event, data, action: "reject", outcome: "rejected", code: "rejected")
      end
      @patches.touch({ interpretation_id: id }, time: event.created_at)
    end

    private

    def propose(event, data)
      id = data.fetch("interpretation_id")
      assessment = { status: data.fetch("assessment"), reasons: [], questions: [] }
      attributes = { interpretation_id: id, message_id: data.fetch("source_message_id"),
        proposed_decision: data.fetch("proposed_decision"), assessment:, proposal_status: data.fetch("assessment"),
        actor_kind: event.metadata.fetch("actor_kind"), actor_id: event.metadata.fetch("actor_id"),
        event_id: event.id, event_type: event.type, stream_context: event.stream.context,
        stream_name: event.stream.stream_name, stream_id: event.stream.stream_id, stream_revision: event.stream_revision,
        causation_id: event.causation_id, correlation_id: event.correlation_id, proposed_at_domain: event.created_at }
        .merge(@sources.fetch(event.id))
      @patches.insert(attributes.merge(lifecycle_status: "proposed", policy_status: "proposal_only",
        adjudication: nil, clarification_required: false, created_at: event.created_at, updated_at: event.created_at))
      @assessments[id] = assessment.merge(@assessments.fetch(id, {})).merge(status: data.fetch("assessment"))
      @patches.assign(attributes.merge(assessment: @assessments.fetch(id)))
    end

    def clarify(event, data)
      id = data.fetch("interpretation_id")
      questions = data.fetch("questions").map.with_index do |prompt, index|
        { field: "clarification_#{index + 1}", prompt:, options: [] }
      end
      @assessments[id] = @assessments.fetch(id, {}).merge(reasons: data.fetch("reasons"), questions:)
      attributes = { interpretation_id: id, lifecycle_status: "clarification_required", clarification_required: true,
        clarification_event_id: event.id, clarification_stream_revision: event.stream_revision,
        clarification_required_at_domain: event.created_at }
      if data.fetch("origin") == "adjudication"
        @assessments[id] = @assessments.fetch(id).merge(status: "needs_classification")
        attributes[:proposal_status] = "needs_classification"
        attributes[:adjudication] = adjudication(event, data, action: "request_clarification", outcome: "clarification_required",
          code: "clarification_required", clarification: { status: "needs_classification", questions: })
      end
      @patches.assign(attributes.merge(assessment: @assessments.fetch(id)))
    end

    def adjudicate(event, data, action:, outcome:, code:, slot: nil)
      @patches.assign(interpretation_id: data.fetch("interpretation_id"), lifecycle_status: action == "accept" ? "accepted" : "rejected",
        clarification_required: false, adjudication: adjudication(event, data, action:, outcome:, code:, slot:))
    end

    def adjudication(event, data, action:, outcome:, code:, slot: nil, clarification: nil)
      { action:, outcome:, rationale: { code:, summary: data.fetch("rationale") }, clarification:, slot:,
        actor: Source.actor(event), event: Source.reference(event), adjudicated_at: event.created_at.utc.iso8601(6),
        causation_id: event.causation_id, correlation_id: event.correlation_id }
    end
  end
end
