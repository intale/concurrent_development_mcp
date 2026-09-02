# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteAdjudicateDecisionInterpretation, :event_store do
  subject(:operation) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:guidance) { Coordinator::Write::Operations::ExecuteRecordGuidance.new(event_store:) }
  let(:proposals) { Coordinator::Write::Operations::ExecuteProposeDecisionInterpretation.new(event_store:) }

  before do
    record_guidance
    propose(command_id: "cmd-proposal-1", interpretation_id: "I-1")
  end

  it "atomically accepts a source proposal and its receipt without activation" do
    result = operation.call(InterpretationInput.adjudication)

    expect(result).to be_success
    accepted = lifecycle_events("M-1").sole
    expect(accepted).to have_attributes(type: "DecisionInterpretationAccepted", stream_revision: 1)
    expect(accepted.markers).to include(
      "message:M-1",
      "interpretation-lifecycle:I-1",
      "command:cmd-adjudication-1",
      a_string_starting_with("compound:interpretation-slot:v2|")
    )
    expect(accepted.data.fetch("proposal_event")).to include(
      "type" => "DecisionInterpretationProposed",
      "stream_id" => "M-1",
      "stream_revision" => 0
    )
    expect(result.value!.data).to have_attributes(
      interpretation_id: "I-1",
      outcome: "accepted_for_activation",
      policy_status: "proposal_only"
    )
    expect(result.value!.data.slot.compound_marker.marker).to be_in(accepted.markers)
    expect(command_events("cmd-adjudication-1")).to contain_exactly(
      have_attributes(type: "CommandCompleted")
    )
  end

  it "records rejection and explicit clarification as distinct command results" do
    rejected = operation.call(
      InterpretationInput.adjudication(
        action: "reject",
        rationale: { code: "incorrect_scope", summary: "Scope is incorrect." }
      )
    )

    expect(rejected).to be_success
    expect(lifecycle_events("M-1").sole.data.fetch("rationale")).to include(
      "code" => "incorrect_scope"
    )

    propose(command_id: "cmd-proposal-2", interpretation_id: "I-2")
    clarified = operation.call(
      InterpretationInput.adjudication(
        command_id: "cmd-adjudication-2",
        interpretation_id: "I-2",
        action: "request_clarification",
        clarification: InterpretationInput.clarification
      )
    )
    clarification = lifecycle_events("M-1").find { _1.data["interpretation_id"] == "I-2" }

    expect(clarified).to be_success
    expect(clarification).to have_attributes(type: "DecisionClarificationRequired")
    expect(clarification.data).to include(
      "origin" => "adjudication",
      "status" => "needs_classification",
      "rationale" => include("code" => "user_confirmed")
    )
  end

  it "replays exactly and denies missing or terminal proposals without new facts" do
    original = operation.call(InterpretationInput.adjudication)
    replay = operation.call(InterpretationInput.adjudication)
    missing = operation.call(
      InterpretationInput.adjudication(
        command_id: "cmd-adjudication-missing",
        interpretation_id: "I-missing"
      )
    )
    terminal = operation.call(
      InterpretationInput.adjudication(
        command_id: "cmd-adjudication-terminal",
        action: "reject"
      )
    )

    expect(replay.value!).to eq(original.value!)
    expect(missing.failure.code).to eq(:interpretation_not_found)
    expect(terminal.failure.code).to eq(:interpretation_already_accepted)
    expect(lifecycle_events("M-1").length).to eq(1)
    expect(command_events("cmd-adjudication-missing")).to be_empty
    expect(command_events("cmd-adjudication-terminal")).to be_empty
  end

  it "serializes concurrent accepts in one canonical slot" do
    propose(command_id: "cmd-proposal-2", interpretation_id: "I-2")
    inputs = [
      InterpretationInput.adjudication(command_id: "cmd-accept-a", interpretation_id: "I-1"),
      InterpretationInput.adjudication(command_id: "cmd-accept-b", interpretation_id: "I-2")
    ]

    results = inputs.map do |input|
      Thread.new { described_class.new(event_store:).call(input) }
    end.map(&:value)

    expect(results.count(&:success?)).to eq(1)
    expect(results.count(&:failure?)).to eq(1)
    expect(results.find(&:failure?).failure.code).to eq(:interpretation_slot_already_accepted)
    expect(lifecycle_events("M-1").count { _1.type == "DecisionInterpretationAccepted" }).to eq(1)
  end

  it "allows concurrent acceptance in disjoint slots" do
    propose(
      command_id: "cmd-proposal-2",
      interpretation_id: "I-2",
      topic_id: "testing.required_suites",
      effect: "require",
      modality: "must",
      value: InterpretationInput.string_set(%w[rspec cucumber])
    )
    inputs = [
      InterpretationInput.adjudication(command_id: "cmd-accept-a", interpretation_id: "I-1"),
      InterpretationInput.adjudication(command_id: "cmd-accept-b", interpretation_id: "I-2")
    ]

    results = inputs.map do |input|
      Thread.new { described_class.new(event_store:).call(input) }
    end.map(&:value)

    expect(results).to all(be_success)
    expect(lifecycle_events("M-1").count { _1.type == "DecisionInterpretationAccepted" }).to eq(2)
  end

  def record_guidance
    guidance.call(
      command_id: "cmd-guidance-1",
      actor: { kind: "user", id: "user-label" },
      message_id: "M-1",
      conversation_id: "C-1",
      source: "mcp_client",
      text: "Use RSpec.",
      anchors: {
        repository_ids: [ RepositoryScenario::DEFAULT_REPOSITORY_ID ],
        change_set_id: "CS-1",
        work_item_id: "W-1",
        attempt_id: nil
      }
    )
  end

  def propose(command_id:, interpretation_id:, **overrides)
    proposals.call(
      InterpretationInput.build(
        command_id:,
        interpretation_id:,
        **overrides
      )
    )
  end

  def lifecycle_events(message_id)
    event_store.read(
      streams.interpretation(message_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[
          DecisionInterpretationAccepted
          DecisionInterpretationRejected
          DecisionClarificationRequired
        ],
        maximum_count: 20,
        direction: :asc
      )
    ).select { _1.data["origin"] == "adjudication" || _1.type != "DecisionClarificationRequired" }
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_COMPLETION)
  end
end
