# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::DecisionInterpretationsV1, :event_store, :read_model do
  subject(:projector) { described_class.new }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }

  before do
    Coordinator::Write::Operations::ExecuteRecordGuidance.new(event_store:).call(
      command_id: "cmd-guidance-project-interpretation",
      actor: { kind: "user", id: "user-label" },
      message_id: "M-project-interpretation",
      conversation_id: "C-project-interpretation",
      source: "mcp_client",
      text: "Do not merge without RSpec.",
      anchors: {
        repository_ids: [ RepositoryScenario::DEFAULT_REPOSITORY_ID ],
        change_set_id: "CS-1",
        work_item_id: nil,
        attempt_id: nil
      }
    ).value!
  end

  it "stores one proposal, applies its clarification and acceptance, and ignores duplicate delivery" do
    enforcement = InterpretationInput.advisory_enforcement.merge(
      level: "merge_gate",
      on_violation: "block"
    )
    Coordinator::Write::Operations::ExecuteProposeDecisionInterpretation.new(event_store:).call(
      InterpretationInput.build(
        command_id: "cmd-project-interpretation",
        interpretation_id: "I-project",
        source_message_id: "M-project-interpretation",
        source_span: { start_character: 21, end_character: 26, text: "RSpec" },
        effect: "forbid",
        modality: "must_not",
        enforcement:
      )
    ).value!
    Coordinator::Write::Operations::ExecuteAdjudicateDecisionInterpretation.new(event_store:).call(
      InterpretationInput.adjudication(
        command_id: "cmd-accept-project-interpretation",
        source_message_id: "M-project-interpretation",
        interpretation_id: "I-project"
      )
    ).value!
    proposal, clarification, acceptance = interpretation_events

    projector.call(proposal)
    projector.call(proposal)
    projector.call(clarification)
    projector.call(clarification)
    projector.call(acceptance)
    projector.call(acceptance)

    projected = Coordinator::Read::Repositories::DecisionInterpretations.new.page(
      Coordinator::Read::InterpretationListQueryV1.new(
        message_id: "M-project-interpretation",
        after_revision: -1,
        limit: 20
      )
    ).records.sole
    expect(projected.to_h).to include(
      interpretation_id: "I-project",
      message_id: "M-project-interpretation",
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
      "compound:interpretation-slot:v1:sha256:"
    )
    expect(projected.adjudication.correlation_id).to eq(acceptance.correlation_id)
    expect(projected.actor.to_h).to eq(
      kind: "agent",
      id: "classifier-host",
      authenticated: false
    )
    expect(projected.causation_id).to be_nil
    expect(Coordinator::Read::DecisionInterpretation.count).to eq(1)
    expect(
      Coordinator::Read::ProcessedProjectionEvent.where(
        projection_name: "decision_interpretations"
      ).count
    ).to eq(3)
  end

  it "serves explicit clarification before a later rejection without activating policy" do
    Coordinator::Write::Operations::ExecuteProposeDecisionInterpretation.new(event_store:).call(
      InterpretationInput.build(
        command_id: "cmd-propose-clarify-project-interpretation",
        interpretation_id: "I-project",
        source_message_id: "M-project-interpretation",
        source_span: { start_character: 21, end_character: 26, text: "RSpec" }
      )
    ).value!
    Coordinator::Write::Operations::ExecuteAdjudicateDecisionInterpretation.new(event_store:).call(
      InterpretationInput.adjudication(
        command_id: "cmd-clarify-project-interpretation",
        source_message_id: "M-project-interpretation",
        interpretation_id: "I-project",
        action: "request_clarification",
        clarification: InterpretationInput.clarification
      )
    ).value!
    Coordinator::Write::Operations::ExecuteAdjudicateDecisionInterpretation.new(event_store:).call(
      InterpretationInput.adjudication(
        command_id: "cmd-reject-project-interpretation",
        source_message_id: "M-project-interpretation",
        interpretation_id: "I-project",
        action: "reject",
        rationale: { code: "user_rejected", summary: "The reading does not match the intended guidance." }
      )
    ).value!
    proposal, clarification, rejection = interpretation_events

    projector.call(proposal)
    projector.call(clarification)
    clarified = projected_interpretation
    expect(clarified.lifecycle_status).to eq("clarification_required")
    expect(clarified.policy_status).to eq("proposal_only")
    expect(clarified.adjudication.to_h).to include(
      action: "request_clarification",
      outcome: "clarification_required",
      clarification: include(status: "needs_classification")
    )

    projector.call(rejection)
    rejected = projected_interpretation
    expect(rejected.lifecycle_status).to eq("rejected")
    expect(rejected.policy_status).to eq("proposal_only")
    expect(rejected.adjudication.to_h).to include(
      action: "reject",
      outcome: "rejected",
      event: include(event_id: rejection.id)
    )
  end

  def interpretation_events
    event_store.read(
      streams.interpretation("M-project-interpretation"),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[
          DecisionInterpretationProposed
          DecisionClarificationRequired
          DecisionInterpretationAccepted
          DecisionInterpretationRejected
        ],
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def projected_interpretation
    Coordinator::Read::Repositories::DecisionInterpretations.new.page(
      Coordinator::Read::InterpretationListQueryV1.new(
        message_id: "M-project-interpretation",
        after_revision: -1,
        limit: 20
      )
    ).records.sole
  end
end
