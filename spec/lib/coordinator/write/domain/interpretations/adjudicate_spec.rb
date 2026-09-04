# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::Interpretations::Adjudicate do
  subject(:decider) { described_class.new }

  let(:proposal) do
    source = Coordinator::Write::Interpretations::GuidanceSourceEvidenceV1.new(
      message_id: "M-1",
      text: "Use RSpec.",
      anchors: Coordinator::Write::GuidanceAnchorsV1.new(
        repository_ids: [ RepositoryScenario::DEFAULT_REPOSITORY_ID ],
        change_set_id: nil,
        work_item_id: nil,
        attempt_id: nil
      ),
      event: event_reference("000001", type: "UserUtteranceRecorded")
    )
    command = Coordinator::Write::Operations::PrepareProposeDecisionInterpretation.new
      .call(InterpretationInput.build(source_span: { start_character: 4, end_character: 9, text: "RSpec" }))
      .value!

    Coordinator::Write::Domain::Interpretations::Propose.new.call(
      state: Coordinator::Write::Domain::Interpretations::State.new(source:, proposal_exists: false),
      command:,
      proposed_at: "2026-08-22T16:00:00.000000Z"
    ).value!.events.first
  end
  let(:proposal_evidence) do
    Coordinator::Write::Interpretations::InterpretationProposalEvidenceV1.new(
      proposal:,
      event: event_reference("000002", type: "DecisionInterpretationProposed")
    )
  end
  let(:slot) { Coordinator::Write::Interpretations::InterpretationSlotBuilder.new.call(proposal) }
  let(:preparer) { Coordinator::Write::Operations::PrepareAdjudicateDecisionInterpretation.new }
  let(:adjudicated_at) { "2026-08-22T17:05:00.000000Z" }

  def command(**overrides)
    preparer.call(InterpretationInput.adjudication(**overrides)).value!
  end

  def state(proposal_value: proposal_evidence, terminal: nil, slot_acceptance: nil)
    Coordinator::Write::Domain::Interpretations::AdjudicationState.new(
      proposal: proposal_value,
      terminal:,
      slot_acceptance:
    )
  end

  def terminal(status:, interpretation_id: "I-1", suffix: "000003")
    Coordinator::Write::Interpretations::InterpretationTerminalEvidenceV1.new(
      status:,
      interpretation_id:,
      event: event_reference(suffix, type: status == "accepted" ? "DecisionInterpretationAccepted" : "DecisionInterpretationRejected")
    )
  end

  def event_reference(suffix, type:)
    Coordinator::Write::EventReference.new(
      event_id: "01900000-0000-7000-8000-000000#{suffix}",
      type:,
      stream_context: "HumanGuidance",
      stream_name: type == "UserUtteranceRecorded" ? "Conversation" : "Interpretation",
      stream_id: type == "UserUtteranceRecorded" ? "C-1" : "M-1",
      stream_revision: 0
    )
  end

  it "implements GDN-03-ACCEPT-01 without activating policy" do
    result = decider.call(state: state, command: command, slot:, adjudicated_at:)

    expect(result).to be_success
    event = result.value!.events.sole
    expect(event).to be_a(Coordinator::Write::Events::DecisionInterpretationAcceptedV2)
    expect(event).to have_attributes(
      interpretation_id: "I-1",
      source_message_id: "M-1",
      slot:,
      rationale: "The proposed reading matches the intended guidance."
    )
  end

  it "implements GDN-03-REJECT-01" do
    result = decider.call(
      state: state,
      command: command(action: "reject", rationale: { code: "incorrect_scope", summary: "Scope is incorrect." }),
      slot:,
      adjudicated_at:
    )

    event = result.value!.events.sole
    expect(event).to be_a(Coordinator::Write::Events::DecisionInterpretationRejectedV2)
    expect(event.rationale).to eq("Scope is incorrect.")
  end

  it "implements GDN-03-CLARIFY-01" do
    result = decider.call(
      state: state,
      command: command(action: "request_clarification", clarification: InterpretationInput.clarification),
      slot:,
      adjudicated_at:
    )

    event = result.value!.events.sole
    expect(event).to be_a(Coordinator::Write::Events::DecisionClarificationRequiredV2)
    expect(event).to have_attributes(origin: "adjudication")
    expect(event.questions.length).to eq(1)
  end

  it "implements GDN-03-NOT-FOUND-01" do
    missing = decider.call(state: state(proposal_value: nil), command: command, slot:, adjudicated_at:)
    mismatched = decider.call(
      state: state,
      command: command(source_message_id: "M-2"),
      slot:,
      adjudicated_at:
    )

    expect([ missing, mismatched ].map { _1.failure.code }).to eq(%i[
      interpretation_not_found
      interpretation_not_found
    ])
  end

  it "implements GDN-03-TERMINAL-01" do
    accepted = decider.call(
      state: state(terminal: terminal(status: "accepted")), command: command(action: "reject"), slot:, adjudicated_at:
    )
    rejected = decider.call(
      state: state(terminal: terminal(status: "rejected")), command: command, slot:, adjudicated_at:
    )

    expect(accepted.failure.code).to eq(:interpretation_already_accepted)
    expect(rejected.failure.code).to eq(:interpretation_already_rejected)
  end

  it "implements GDN-03-SLOT-CONFLICT-01" do
    acceptance = terminal(status: "accepted", interpretation_id: "I-B", suffix: "000004")

    result = decider.call(
      state: state(slot_acceptance: acceptance),
      command: command,
      slot:,
      adjudicated_at:
    )

    expect(result.failure).to have_attributes(code: :interpretation_slot_already_accepted)
    expect(result.failure.details).to include(
      interpretation_id: "I-B",
      slot_digest: slot.compound_marker.digest
    )
  end
end
