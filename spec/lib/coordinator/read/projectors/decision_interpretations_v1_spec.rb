# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::DecisionInterpretationsV1, :read_model do
  subject(:projector) do
    described_class.new(
      source_loader: Coordinator::Read::Interpretations::ProjectionSourceLoader.new(
        event_store: Coordinator::Container["event_store"]
      )
    )
  end

  let(:message_id) { "M-project-interpretation" }
  let(:interpretation_id) { "I-project" }
  let(:stream) { Coordinator::Write::StreamFactory.new.interpretation(message_id) }
  let(:correlation_id) { SecureRandom.uuid_v7 }

  it "stores one proposal, clarification, and acceptance while ignoring duplicate delivery" do
    proposal, clarification, acceptance = accepted_events

    [ proposal, proposal, clarification, clarification, acceptance, acceptance ].each do
      projector.call(_1)
    end

    projected = projected_interpretation
    expect(projected.to_h).to include(
      interpretation_id:,
      message_id:,
      lifecycle_status: "accepted",
      policy_status: "proposal_only"
    )
    expect(projected.assessment.status).to eq("confirmation_required")
    expect(projected.event.to_h).to include(
      event_id: proposal.id,
      type: "DecisionInterpretationProposed",
      stream_revision: 0
    )
    expect(projected.clarification_event.to_h).to include(
      event_id: clarification.id,
      type: "DecisionClarificationRequired",
      stream_revision: 1
    )
    expect(projected.source_event.type).to eq("UserUtteranceRecorded")
    expect(projected.adjudication.to_h).to include(
      action: "accept",
      outcome: "accepted_for_activation",
      rationale: include(code: "user_confirmed"),
      event: include(event_id: acceptance.id, type: "DecisionInterpretationAccepted"),
      actor: include(kind: "orchestrator", id: "guidance-host", authenticated: false)
    )
    expect(projected.adjudication.slot.compound_marker.marker).to start_with(
      "compound:interpretation-slot:v2|"
    )
    expect(projected.adjudication.correlation_id).to eq(acceptance.correlation_id)
    expect(projected.actor.to_h).to eq(
      kind: "agent",
      id: "classifier-host",
      authenticated: false
    )
    expect(projected.causation_id).to be_nil
    expect(Coordinator::Read::DecisionInterpretation.count).to eq(1)
    expect(processed_events.count).to eq(3)
  end

  it "serves explicit clarification before a later rejection without activating policy" do
    proposal = proposal_event
    clarification = interpretation_event(
      Coordinator::Write::Events::DecisionClarificationRequiredV1.new(
        interpretation_id:,
        source_message_id: message_id,
        status: "needs_classification",
        origin: "adjudication",
        reasons: [ "scope_unclear" ],
        questions: [ clarification_question ],
        rationale: rationale("scope_unclear", "The intended repository is unclear."),
        required_at: "2026-08-30T12:01:00.000000Z"
      ),
      revision: 1,
      position: 200,
      actor_kind: "orchestrator",
      actor_id: "guidance-host",
      causation_id: proposal.id
    )
    rejection = interpretation_event(
      Coordinator::Write::Events::DecisionInterpretationRejectedV1.new(
        interpretation_id:,
        source_message_id: message_id,
        proposal_event: event_reference(proposal),
        rationale: rationale("user_rejected", "The reading does not match the intended guidance."),
        rejected_at: "2026-08-30T12:02:00.000000Z"
      ),
      revision: 2,
      position: 300,
      actor_kind: "orchestrator",
      actor_id: "guidance-host",
      causation_id: proposal.id
    )

    projector.call(proposal)
    projector.call(clarification)
    clarified = projected_interpretation
    expect(clarified).to have_attributes(
      lifecycle_status: "clarification_required",
      policy_status: "proposal_only"
    )
    expect(clarified.adjudication.to_h).to include(
      action: "request_clarification",
      outcome: "clarification_required",
      clarification: include(status: "needs_classification")
    )

    projector.call(rejection)
    rejected = projected_interpretation
    expect(rejected).to have_attributes(lifecycle_status: "rejected", policy_status: "proposal_only")
    expect(rejected.adjudication.to_h).to include(
      action: "reject",
      outcome: "rejected",
      event: include(event_id: rejection.id)
    )
  end

  def accepted_events
    proposal = proposal_event
    clarification = interpretation_event(
      Coordinator::Write::Events::DecisionClarificationRequiredV1.new(
        interpretation_id:,
        source_message_id: message_id,
        status: "confirmation_required",
        origin: "proposal_assessment",
        reasons: %w[hard_constraint high_impact_enforcement],
        questions: [ confirmation_question ],
        rationale: nil,
        required_at: "2026-08-30T12:00:00.000000Z"
      ),
      revision: 1,
      position: 200,
      causation_id: proposal.id
    )
    acceptance = interpretation_event(
      Coordinator::Write::Events::DecisionInterpretationAcceptedV1.new(
        interpretation_id:,
        source_message_id: message_id,
        proposal_event: event_reference(proposal),
        slot: Coordinator::Write::Interpretations::InterpretationSlotBuilder.new.call(
          proposal_payload
        ),
        rationale: rationale("user_confirmed", "The proposed reading matches the intended guidance."),
        accepted_at: "2026-08-30T12:01:00.000000Z"
      ),
      revision: 2,
      position: 300,
      actor_kind: "orchestrator",
      actor_id: "guidance-host",
      causation_id: proposal.id
    )
    [ proposal, clarification, acceptance ]
  end

  def proposal_event
    interpretation_event(proposal_payload, revision: 0, position: 100, actor_id: "classifier-host")
  end

  def proposal_payload
    @proposal_payload ||= begin
      input = InterpretationInput.build(
        interpretation_id:,
        source_message_id: message_id,
        source_span: { start_character: 21, end_character: 26, text: "RSpec" },
        effect: "forbid",
        modality: "must_not",
        scope: InterpretationInput.scope(
          repository_ids: [ "018f0f4d-4e45-7abc-8def-000000000001" ],
          change_set_id: "CS-1"
        ),
        enforcement: InterpretationInput.advisory_enforcement.merge(
          level: "merge_gate",
          on_violation: "block"
        )
      )
      Coordinator::Write::Events::DecisionInterpretationProposedV1.new(
        interpretation_id:,
        source_message_id: message_id,
        source_event: Coordinator::Write::EventReference.new(
          event_id: SecureRandom.uuid_v7,
          type: "UserUtteranceRecorded",
          stream_context: "HumanGuidance",
          stream_name: "Conversation",
          stream_id: "C-project-interpretation",
          stream_revision: 0
        ),
        source_span: input.fetch(:source_span),
        classifier: input.fetch(:classifier),
        proposed_decision: input.fetch(:proposed_decision),
        scope_provenance: {
          kind: "explicit",
          anchor_level: "change_set",
          source_message_id: message_id
        },
        ambiguities: [],
        assessment: {
          status: "confirmation_required",
          reasons: %w[hard_constraint high_impact_enforcement],
          questions: [ confirmation_question ]
        },
        proposed_at: "2026-08-30T12:00:00.000000Z"
      )
    end
  end

  def confirmation_question
    Coordinator::Write::Interpretations::ClarificationQuestionV1.new(
      field: "confirmation",
      prompt: "Confirm or revise this high-impact interpretation.",
      options: %w[confirm revise]
    )
  end

  def clarification_question
    Coordinator::Write::Interpretations::ClarificationQuestionV1.new(
      field: "scope",
      prompt: "Which repository should this interpretation govern?",
      options: %w[billing orders]
    )
  end

  def rationale(code, summary)
    Coordinator::Write::Interpretations::AdjudicationRationaleV1.new(code:, summary:)
  end

  def interpretation_event(
    payload,
    revision:,
    position:,
    actor_kind: "agent",
    actor_id: "classifier-host",
    causation_id: nil
  )
    ProjectionEventFactory.build(
      payload:,
      stream:,
      stream_revision: revision,
      global_position: position,
      policy_version: "decision-interpretation/v1",
      actor_kind:,
      actor_id:,
      correlation_id:,
      causation_id:
    )
  end

  def event_reference(event)
    Coordinator::Write::EventReference.new(
      event_id: event.id,
      type: event.type,
      stream_context: event.stream.context,
      stream_name: event.stream.stream_name,
      stream_id: event.stream.stream_id,
      stream_revision: event.stream_revision
    )
  end

  def projected_interpretation
    Coordinator::Read::Repositories::DecisionInterpretations.new.page(
      Coordinator::Read::InterpretationListQueryV1.new(
        message_id:,
        after_revision: -1,
        limit: 20
      )
    ).records.sole
  end

  def processed_events
    Coordinator::Read::ProcessedProjectionEvent.where(
      projection_name: "decision_interpretations"
    )
  end
end
