# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteCorrectDecision, :event_store do
  subject(:operation) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:guidance) { Coordinator::Write::Operations::ExecuteRecordGuidance.new(event_store:) }
  let(:proposals) { Coordinator::Write::Operations::ExecuteProposeDecisionInterpretation.new(event_store:) }
  let(:adjudications) { Coordinator::Write::Operations::ExecuteAdjudicateDecisionInterpretation.new(event_store:) }
  let(:activations) { Coordinator::Write::Operations::ExecuteActivateDecision.new(event_store:) }

  it "implements DEC-02A-CORRECT-SAME-SLOT-01 and exact replay atomically" do
    activation = seed_active_decision
    seed_correction(value: InterpretationInput.named_choice("minitest"))
    input = InterpretationInput.correction(expected_head: reference(activation))

    original = operation.call(input)
    replay = operation.call(input)

    expect(original).to be_success
    expect(replay.value!).to eq(original.value!)
    expect(decision_events("D-1").map(&:type)).to eq(
      %w[DecisionRecorded DecisionActivated DecisionDefinitionCorrected]
    )
    correction = decision_events("D-1").last
    expect(correction).to have_attributes(stream_revision: 2)
    expect(correction.data.fetch("previous_head").fetch("event")).to include(
      "event_id" => activation.id,
      "type" => "DecisionActivated",
      "stream_revision" => 1
    )
    expect(correction.markers).to include(
      "decision:D-1",
      "interpretation-correction:I-2",
      "topic:testing.framework",
      "topic-root:testing",
      "command:cmd-decision-correction-1"
    )

    slot_id = original.value!.data.slot.slot_id
    heads = slot_events(slot_id).select { _1.type == "DecisionSlotHeadChanged" }
    expect(heads.length).to eq(2)
    expect(heads.last.data.fetch("head")).to include(
      "decision_id" => "D-1",
      "decision_revision" => 2
    )
    expect(partition_events("repo:billing:testing").map(&:stream_revision)).to eq([ 0, 1 ])
    expect(original.value!.data).to have_attributes(
      outcome: "corrected",
      policy_status: "active",
      correction_event: have_attributes(type: "DecisionDefinitionCorrected", stream_revision: 2)
    )
    expect(command_events("cmd-decision-correction-1").length).to eq(1)
  end

  it "implements DEC-02A-CORRECT-NARROW-SCOPE-01 by moving the slot and advancing both partitions" do
    activation = seed_active_decision
    old_slot_id = load(activation).slot.slot_id
    seed_correction(
      scope: InterpretationInput.scope(
        repository_ids: [ "billing" ],
        work_item_id: "W-42"
      )
    )

    result = operation.call(InterpretationInput.correction(expected_head: reference(activation)))

    expect(result).to be_success
    new_slot_id = result.value!.data.slot.slot_id
    expect(new_slot_id).not_to eq(old_slot_id)
    expect(slot_events(old_slot_id).last.data.fetch("head")).to be_nil
    expect(slot_events(new_slot_id).map(&:type)).to eq(%w[DecisionSlotOpened DecisionSlotHeadChanged])
    expect(partition_events("repo:billing:testing").map(&:stream_revision)).to eq([ 0, 1 ])
    expect(partition_events("workitem:W-42:testing").map(&:stream_revision)).to eq([ 0 ])
    expect(result.value!.data.partitions.map { _1.partition.partition_id }).to eq(
      %w[repo:billing:testing workitem:W-42:testing]
    )
  end

  it "implements DEC-02A-WRONG-RELATION-01 without correction facts" do
    activation = seed_active_decision
    seed_correction(relations: { corrects: [], supersedes: [ "D-1" ], exception_to: [], revokes: [] })

    result = operation.call(InterpretationInput.correction(expected_head: reference(activation)))

    expect(result).to be_failure
    expect(result.failure.code).to eq(:interpretation_not_a_correction)
    expect(decision_events("D-1").map(&:type)).to eq(%w[DecisionRecorded DecisionActivated])
    expect(command_events("cmd-decision-correction-1")).to be_empty
  end

  it "implements DEC-02A-SLOT-OCCUPIED-01 without clearing the current slot" do
    first_activation = seed_active_decision
    seed_active_decision(
      decision_id: "D-2",
      interpretation_id: "I-target",
      message_id: "M-target",
      command_suffix: "target",
      scope: InterpretationInput.scope(repository_ids: [ "billing" ], work_item_id: "W-42")
    )
    seed_correction(
      scope: InterpretationInput.scope(repository_ids: [ "billing" ], work_item_id: "W-42")
    )

    result = operation.call(InterpretationInput.correction(expected_head: reference(first_activation)))

    expect(result).to be_failure
    expect(result.failure).to have_attributes(code: :decision_slot_occupied)
    expect(decision_events("D-1").map(&:type)).to eq(%w[DecisionRecorded DecisionActivated])
    original_slot = load(first_activation).slot.slot_id
    expect(load(slot_events(original_slot).last).head.decision_id).to eq("D-1")
  end

  it "implements DEC-02A-SAME-DECISION-RACE-01 with one complete winner" do
    activation = seed_active_decision
    seed_correction(
      interpretation_id: "I-correction-a",
      message_id: "M-correction-a",
      command_suffix: "correction-a",
      value: InterpretationInput.named_choice("minitest")
    )
    seed_correction(
      interpretation_id: "I-correction-b",
      message_id: "M-correction-b",
      command_suffix: "correction-b",
      value: InterpretationInput.named_choice("test-unit")
    )
    expected_head = reference(activation)
    inputs = [
      InterpretationInput.correction(
        command_id: "cmd-correction-a",
        interpretation_id: "I-correction-a",
        expected_head:
      ),
      InterpretationInput.correction(
        command_id: "cmd-correction-b",
        interpretation_id: "I-correction-b",
        expected_head:
      )
    ]

    results = inputs.map do |input|
      Thread.new { described_class.new(event_store:).call(input) }
    end.map(&:value)

    expect(results.count(&:success?)).to eq(1)
    expect(results.count(&:failure?)).to eq(1)
    expect(results.find(&:failure?).failure.code).to eq(:decision_revision_changed)
    expect(decision_events("D-1").map(&:type)).to eq(
      %w[DecisionRecorded DecisionActivated DecisionDefinitionCorrected]
    )
    expect(partition_events("repo:billing:testing").map(&:stream_revision)).to eq([ 0, 1 ])
  end

  it "implements DEC-02A-PARTITION-LIMIT-01 over the old/new partition union" do
    old_repositories = 32.times.map { "old-#{_1}" }
    new_repositories = 32.times.map { "new-#{_1}" }
    activation = seed_active_decision(
      topic_id: "testing.required_suites",
      effect: "require",
      modality: "must",
      value: InterpretationInput.string_set([ "rspec" ]),
      scope: InterpretationInput.scope(repository_ids: old_repositories)
    )
    seed_correction(
      topic_id: "testing.required_suites",
      effect: "require",
      modality: "must",
      value: InterpretationInput.string_set([ "rspec", "cucumber" ]),
      scope: InterpretationInput.scope(repository_ids: new_repositories)
    )

    result = operation.call(InterpretationInput.correction(expected_head: reference(activation)))

    expect(result).to be_failure
    expect(result.failure).to have_attributes(code: :decision_partition_limit_reached)
    expect(decision_events("D-1").map(&:type)).to eq(%w[DecisionRecorded DecisionActivated])
  end

  def seed_active_decision(
    decision_id: "D-1",
    interpretation_id: "I-1",
    message_id: "M-1",
    command_suffix: "1",
    **proposal_overrides
  )
    seed_accepted_interpretation(
      interpretation_id:,
      message_id:,
      command_suffix:,
      **proposal_overrides
    )
    result = activations.call(
      InterpretationInput.activation(
        command_id: "cmd-activation-#{command_suffix}",
        decision_id:,
        interpretation_id:
      )
    )
    raise result.failure.inspect if result.failure?

    decision_events(decision_id).find { _1.type == "DecisionActivated" }
  end

  def seed_correction(
    interpretation_id: "I-2",
    message_id: "M-2",
    command_suffix: "2",
    relations: { corrects: [ "D-1" ], supersedes: [], exception_to: [], revokes: [] },
    **proposal_overrides
  )
    seed_accepted_interpretation(
      interpretation_id:,
      message_id:,
      command_suffix:,
      relations:,
      **proposal_overrides
    )
  end

  def seed_accepted_interpretation(
    interpretation_id:,
    message_id:,
    command_suffix:,
    **proposal_overrides
  )
    guidance_result = guidance.call(
      command_id: "cmd-guidance-#{command_suffix}",
      actor: { kind: "user", id: "user-label" },
      message_id:,
      conversation_id: "C-#{command_suffix}",
      source: "mcp_client",
      text: "Use RSpec.",
      anchors: {
        repository_ids: [ "billing" ],
        change_set_id: nil,
        work_item_id: nil,
        attempt_id: nil
      }
    )
    raise guidance_result.failure.inspect if guidance_result.failure?

    proposal_result = proposals.call(
      InterpretationInput.build(
        command_id: "cmd-proposal-#{command_suffix}",
        interpretation_id:,
        source_message_id: message_id,
        **proposal_overrides
      )
    )
    raise proposal_result.failure.inspect if proposal_result.failure?

    adjudication_result = adjudications.call(
      InterpretationInput.adjudication(
        command_id: "cmd-adjudication-#{command_suffix}",
        source_message_id: message_id,
        interpretation_id:
      )
    )
    raise adjudication_result.failure.inspect if adjudication_result.failure?
  end

  def decision_events(decision_id)
    event_store.read(
      streams.decision(decision_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[DecisionRecorded DecisionActivated DecisionDefinitionCorrected],
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def slot_events(slot_id)
    event_store.read(
      streams.decision_slot(slot_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[DecisionSlotOpened DecisionSlotHeadChanged],
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def partition_events(partition_id)
    event_store.read(
      streams.decision_partition(partition_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "DecisionPartitionAdvanced" ],
        maximum_count: 40,
        direction: :asc
      )
    )
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_COMPLETION)
  end

  def reference(event)
    {
      event_id: event.id,
      type: event.type,
      stream_context: event.stream.context,
      stream_name: event.stream.stream_name,
      stream_id: event.stream.stream_id,
      stream_revision: event.stream_revision
    }
  end

  def load(event)
    Coordinator::Write::EventSchemaRegistry.new.load(
      type: event.type,
      schema_version: event.metadata.fetch("schema_version"),
      data: event.data
    )
  end
end
