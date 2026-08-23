# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteProposeDecisionInterpretation, :event_store do
  subject(:operation) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:guidance) { Coordinator::Write::Operations::ExecuteRecordGuidance.new(event_store:) }

  before { record_guidance }

  it "atomically persists a source-bound proposal and its receipt" do
    result = operation.call(InterpretationInput.build)

    expect(result).to be_success
    fact = interpretation_events("M-1").sole
    expect(fact).to have_attributes(type: "DecisionInterpretationProposed", stream_revision: 0)
    expect(fact.markers).to include(
      "message:M-1",
      "interpretation:I-1",
      "command:cmd-interpretation-1"
    )
    expect(fact.data).to include(
      "interpretation_id" => "I-1",
      "source_message_id" => "M-1",
      "assessment" => include("status" => "accepted_for_activation")
    )
    expect(fact.data.fetch("source_event")).to include(
      "type" => "UserUtteranceRecorded",
      "stream_context" => "HumanGuidance",
      "stream_name" => "Conversation"
    )
    expect(result.value!.data.assessment.status).to eq("accepted_for_activation")
    expect(command_events("cmd-interpretation-1").one?).to be(true)
  end

  it "atomically persists a hard proposal and its clarification requirement" do
    enforcement = InterpretationInput.advisory_enforcement.merge(
      level: "merge_gate",
      on_violation: "block"
    )
    input = InterpretationInput.build(
      effect: "forbid",
      modality: "must_not",
      enforcement:
    )

    result = operation.call(input)
    facts = interpretation_events("M-1")

    expect(result).to be_success
    expect(facts.map(&:type)).to eq(%w[
      DecisionInterpretationProposed
      DecisionClarificationRequired
    ])
    expect(facts.map(&:stream_revision)).to eq([ 0, 1 ])
    expect(result.value!.data.assessment.status).to eq("confirmation_required")
    expect(result.value!.emitted_events.map(&:type)).to eq(facts.map(&:type))
  end

  it "replays exactly and denies source or proposal identity violations without facts" do
    original = operation.call(InterpretationInput.build)
    replay = operation.call(InterpretationInput.build)
    missing = operation.call(
      InterpretationInput.build(
        command_id: "cmd-interpretation-missing",
        interpretation_id: "I-missing",
        source_message_id: "M-missing"
      )
    )
    mismatch = operation.call(
      InterpretationInput.build(
        command_id: "cmd-interpretation-span",
        interpretation_id: "I-span",
        source_span: { start_character: 0, end_character: 3, text: "bad" }
      )
    )
    duplicate = operation.call(
      InterpretationInput.build(command_id: "cmd-interpretation-duplicate")
    )

    expect(replay.value!).to eq(original.value!)
    expect([ missing, mismatch, duplicate ].map { _1.failure.code }).to eq(%i[
      guidance_message_not_found
      source_span_mismatch
      interpretation_already_proposed
    ])
    expect(interpretation_events("M-1").length).to eq(1)
    expect(command_events("cmd-interpretation-missing")).to be_empty
    expect(command_events("cmd-interpretation-span")).to be_empty
    expect(command_events("cmd-interpretation-duplicate")).to be_empty
  end

  it "allows distinct classifier proposals for one message to commit concurrently" do
    inputs = [
      InterpretationInput.build(command_id: "cmd-proposal-a", interpretation_id: "I-A"),
      InterpretationInput.build(
        command_id: "cmd-proposal-b",
        interpretation_id: "I-B",
        topic_id: "testing.required_suites",
        effect: "require",
        modality: "must",
        value: InterpretationInput.string_set(%w[rspec cucumber])
      )
    ]

    results = inputs.map do |input|
      Thread.new { described_class.new(event_store:).call(input) }
    end.map(&:value)

    expect(results).to all(be_success)
    expect(interpretation_events("M-1").count { _1.type == "DecisionInterpretationProposed" }).to eq(2)
    expect(inputs.all? { command_events(_1.fetch(:command_id)).one? }).to be(true)
  end

  it "accepts every exact Candidate impact policy level through the public preparer" do
    levels = Coordinator::Shared::Types::CANDIDATE_IMPACT_POLICY_ENFORCEMENT_LEVELS
    results = levels.each_with_index.map do |level, index|
      operation.call(
        InterpretationInput.impact_policy(
          level:,
          command_id: "cmd-impact-policy-#{index}",
          interpretation_id: "I-impact-policy-#{index}",
          source_message_id: "M-1",
          required_evidence: %w[combined_tests contract_compatibility_review]
        )
      )
    end

    expect(results).to all(be_success)
    proposals = interpretation_events("M-1").select { _1.type == "DecisionInterpretationProposed" }
    expect(proposals.map { _1.data.dig("proposed_decision", "enforcement", "level") }).to eq(levels)
    expect(proposals.map { _1.data.dig("assessment", "status") }.uniq).to eq([ "confirmation_required" ])
    expect(levels.each_index.all? { command_events("cmd-impact-policy-#{_1}").one? }).to be(true)
  end

  it "serializes a concurrent global interpretation ID claim" do
    record_guidance(
      command_id: "cmd-guidance-2",
      message_id: "M-2",
      conversation_id: "C-2",
      text: "Use RSpec."
    )
    inputs = [
      InterpretationInput.build(command_id: "cmd-id-race-a", interpretation_id: "I-race"),
      InterpretationInput.build(
        command_id: "cmd-id-race-b",
        interpretation_id: "I-race",
        source_message_id: "M-2"
      )
    ]

    results = inputs.map do |input|
      Thread.new { described_class.new(event_store:).call(input) }
    end.map(&:value)

    expect(results.count(&:success?)).to eq(1)
    expect(results.count(&:failure?)).to eq(1)
    expect(results.find(&:failure?).failure.code).to eq(:interpretation_already_proposed)
    expect(global_proposals("I-race").length).to eq(1)
  end

  def record_guidance(
    command_id: "cmd-guidance-1",
    message_id: "M-1",
    conversation_id: "C-1",
    text: "Use RSpec."
  )
    guidance.call(
      command_id:,
      actor: { kind: "user", id: "user-label" },
      message_id:,
      conversation_id:,
      source: "mcp_client",
      text:,
      anchors: {
        repository_ids: [ "billing" ],
        change_set_id: "CS-1",
        work_item_id: "W-1",
        attempt_id: nil
      }
    )
  end

  def interpretation_events(message_id)
    event_store.read(
      streams.interpretation(message_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[DecisionInterpretationProposed DecisionClarificationRequired],
        maximum_count: 20,
        direction: :asc
      )
    )
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_COMPLETION)
  end

  def global_proposals(interpretation_id)
    event_store.read_global_marked(
      Coordinator::Write::EventQueries.interpretation_proposal("interpretation:#{interpretation_id}")
    )
  end
end
