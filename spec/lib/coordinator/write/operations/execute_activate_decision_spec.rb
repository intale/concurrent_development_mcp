# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteActivateDecision, :event_store do
  subject(:operation) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:guidance) { Coordinator::Write::Operations::ExecuteRecordGuidance.new(event_store:) }
  let(:proposals) { Coordinator::Write::Operations::ExecuteProposeDecisionInterpretation.new(event_store:) }
  let(:adjudications) { Coordinator::Write::Operations::ExecuteAdjudicateDecisionInterpretation.new(event_store:) }

  it "implements DEC-01-ACTIVATE-01 and exact replay atomically" do
    seed_accepted_interpretation

    original = operation.call(InterpretationInput.activation)
    replay = operation.call(InterpretationInput.activation)

    expect(original).to be_success
    expect(replay.value!).to eq(original.value!)
    expect(decision_events("D-1").map(&:type)).to eq(%w[DecisionRecorded DecisionActivated])
    expect(decision_events("D-1").map(&:stream_revision)).to eq([ 0, 1 ])
    activation = decision_events("D-1").last
    expect(activation.markers).to include(
      "decision:D-1",
      "interpretation-activation:I-1",
      "topic:testing.framework",
      "topic-root:testing",
      "command:cmd-decision-activation-1",
      a_string_starting_with("compound:decision-slot:v1:sha256:")
    )
    expect(activation.data.fetch("recorded_event")).to include(
      "type" => "DecisionRecorded",
      "stream_id" => "D-1",
      "stream_revision" => 0
    )

    slot = original.value!.data.slot
    expect(slot_events(slot.slot_id).map(&:type)).to eq(%w[DecisionSlotOpened DecisionSlotHeadChanged])
    receipt_partition = original.value!.data.partitions.sole
    expect(receipt_partition.partition).to have_attributes(
      partition_id: "repo:billing:testing",
      anchor_kind: "repo",
      anchor_id: "billing"
    )
    expect(receipt_partition.partition_revision).to eq(0)
    expect(partition_events("repo:billing:testing").sole).to have_attributes(
      type: "DecisionPartitionAdvanced",
      stream_revision: 0
    )
    expect(load(partition_events("repo:billing:testing").sole).active_decisions).to contain_exactly(
      have_attributes(decision_id: "D-1", decision_revision: 1)
    )
    expect(command_events("cmd-decision-activation-1").length).to eq(1)
  end

  it "implements DEC-01-NOT-ACCEPTED-01 without facts" do
    seed_proposal(interpretation_id: "I-1", message_id: "M-1")

    result = operation.call(InterpretationInput.activation)

    expect(result).to be_failure
    expect(result.failure.code).to eq(:interpretation_not_accepted)
    expect(decision_events("D-1")).to be_empty
    expect(command_events("cmd-decision-activation-1")).to be_empty
  end

  it "denies a reused Decision ID and an already activated interpretation" do
    seed_accepted_interpretation
    first = operation.call(InterpretationInput.activation)
    seed_accepted_interpretation(
      interpretation_id: "I-2",
      message_id: "M-2",
      command_suffix: "2"
    )

    reused_decision = operation.call(
      InterpretationInput.activation(
        command_id: "cmd-reused-decision",
        interpretation_id: "I-2"
      )
    )
    reused_interpretation = operation.call(
      InterpretationInput.activation(
        command_id: "cmd-reused-interpretation",
        decision_id: "D-2"
      )
    )

    expect(first).to be_success
    expect(reused_decision.failure.code).to eq(:decision_already_exists)
    expect(reused_interpretation.failure.code).to eq(:interpretation_already_activated)
    expect(decision_events("D-1").length).to eq(2)
    expect(decision_events("D-2")).to be_empty
  end

  it "implements conservative activation eligibility and the partition limit" do
    seed_accepted_interpretation(
      statement_kind: "question",
      interpretation_id: "I-question",
      message_id: "M-question",
      command_suffix: "question"
    )
    ineligible = operation.call(
      InterpretationInput.activation(
        command_id: "cmd-activate-question",
        decision_id: "D-question",
        interpretation_id: "I-question"
      )
    )

    repositories = 33.times.map { "repo-#{_1}" }
    seed_accepted_interpretation(
      interpretation_id: "I-wide",
      message_id: "M-wide",
      command_suffix: "wide",
      scope: InterpretationInput.scope(repository_ids: repositories)
    )
    too_wide = operation.call(
      InterpretationInput.activation(
        command_id: "cmd-activate-wide",
        decision_id: "D-wide",
        interpretation_id: "I-wide"
      )
    )

    expect(ineligible.failure).to have_attributes(code: :decision_definition_not_activatable)
    expect(ineligible.failure.details.fetch(:reasons)).to eq([ "non_normative_statement_kind" ])
    expect(too_wide.failure).to have_attributes(code: :decision_partition_limit_reached)
    expect(decision_events("D-question")).to be_empty
    expect(decision_events("D-wide")).to be_empty
  end

  it "implements DEC-01-SLOT-RACE-01 with one complete winner" do
    seed_accepted_interpretation(
      interpretation_id: "I-A",
      message_id: "M-A",
      command_suffix: "a"
    )
    seed_accepted_interpretation(
      interpretation_id: "I-B",
      message_id: "M-B",
      command_suffix: "b"
    )
    inputs = [
      InterpretationInput.activation(command_id: "cmd-activate-a", decision_id: "D-A", interpretation_id: "I-A"),
      InterpretationInput.activation(command_id: "cmd-activate-b", decision_id: "D-B", interpretation_id: "I-B")
    ]

    results = inputs.map do |input|
      Thread.new { described_class.new(event_store:).call(input) }
    end.map(&:value)

    expect(results.count(&:success?)).to eq(1)
    expect(results.count(&:failure?)).to eq(1)
    expect(results.find(&:failure?).failure.code).to eq(:decision_slot_occupied)
    expect(%w[D-A D-B].sum { decision_events(_1).length }).to eq(2)
    expect(partition_events("repo:billing:testing").length).to eq(1)
  end

  it "implements DEC-01-SET-UNION-01 with successive partition revisions" do
    seed_accepted_interpretation(
      interpretation_id: "I-A",
      message_id: "M-A",
      command_suffix: "a",
      topic_id: "testing.required_suites",
      effect: "require",
      modality: "must",
      value: InterpretationInput.string_set(%w[rspec cucumber])
    )
    seed_accepted_interpretation(
      interpretation_id: "I-B",
      message_id: "M-B",
      command_suffix: "b",
      topic_id: "testing.required_suites",
      effect: "require",
      modality: "must",
      value: InterpretationInput.string_set(%w[rspec mutation])
    )
    inputs = [
      InterpretationInput.activation(command_id: "cmd-activate-a", decision_id: "D-A", interpretation_id: "I-A"),
      InterpretationInput.activation(command_id: "cmd-activate-b", decision_id: "D-B", interpretation_id: "I-B")
    ]

    results = inputs.map do |input|
      Thread.new { described_class.new(event_store:).call(input) }
    end.map(&:value)

    expect(results).to all(be_success)
    expect(results.map { _1.value!.data.slot }).to all(be_nil)
    partition_history = partition_events("repo:billing:testing")
    expect(partition_history.map(&:stream_revision)).to eq([ 0, 1 ])
    expect(load(partition_history.first).active_decisions.map(&:decision_id)).to eq([ "D-A" ])
    expect(load(partition_history.last).active_decisions.map(&:decision_id)).to eq(%w[D-A D-B])
    expect(results.map { _1.value!.data.partitions.sole.partition_revision }.sort).to eq([ 0, 1 ])
  end

  it "activates every exact Candidate impact policy into its ChangeSet Candidate partition" do
    levels = Coordinator::Shared::Types::CANDIDATE_IMPACT_POLICY_ENFORCEMENT_LEVELS

    results = levels.each_with_index.map do |level, index|
      suffix = "impact-#{index}"
      change_set_id = "CS-impact-#{index}"
      seed_accepted_interpretation(
        interpretation_id: "I-#{suffix}",
        message_id: "M-#{suffix}",
        command_suffix: suffix,
        **InterpretationInput.impact_policy_attributes(level:, change_set_id:)
      )
      operation.call(
        InterpretationInput.activation(
          command_id: "cmd-activate-#{suffix}",
          decision_id: "D-#{suffix}",
          interpretation_id: "I-#{suffix}"
        )
      )
    end

    expect(results).to all(be_success)
    results.each_with_index do |result, index|
      level = levels.fetch(index)
      recorded = load(decision_events("D-impact-#{index}").first)
      expect(recorded.definition.document).to have_attributes(
        topic_root: "candidate",
        enforcement: have_attributes(level:)
      )
      expect(result.value!.data.partitions.sole.partition).to have_attributes(
        partition_id: "changeset:CS-impact-#{index}:candidate",
        anchor_kind: "changeset",
        anchor_id: "CS-impact-#{index}"
      )
    end
  end

  it "denies an activation that would exceed the bounded active-head snapshot" do
    seed_accepted_interpretation(
      interpretation_id: "I-A",
      message_id: "M-A",
      command_suffix: "a",
      topic_id: "testing.required_suites",
      effect: "require",
      modality: "must",
      value: InterpretationInput.string_set([ "rspec" ])
    )
    seed_accepted_interpretation(
      interpretation_id: "I-B",
      message_id: "M-B",
      command_suffix: "b",
      topic_id: "testing.required_suites",
      effect: "require",
      modality: "must",
      value: InterpretationInput.string_set([ "cucumber" ])
    )
    bounded_operation = described_class.new(
      event_store:,
      decider: Coordinator::Write::Domain::Decisions::Activate.new(maximum_active_decisions: 1)
    )

    first = bounded_operation.call(
      InterpretationInput.activation(command_id: "cmd-activate-a", decision_id: "D-A", interpretation_id: "I-A")
    )
    second = bounded_operation.call(
      InterpretationInput.activation(command_id: "cmd-activate-b", decision_id: "D-B", interpretation_id: "I-B")
    )

    expect(first).to be_success
    expect(second.failure).to have_attributes(
      code: :decision_partition_capacity_reached,
      details: include(
        partition_id: "repo:billing:testing",
        active_decision_count: 1,
        maximum_active_decisions: 1
      )
    )
    expect(decision_events("D-B")).to be_empty
    expect(load(partition_events("repo:billing:testing").sole).active_decisions.map(&:decision_id)).to eq([ "D-A" ])
  end

  def seed_accepted_interpretation(
    interpretation_id: "I-1",
    message_id: "M-1",
    command_suffix: "1",
    **proposal_overrides
  )
    seed_proposal(
      interpretation_id:,
      message_id:,
      command_suffix:,
      **proposal_overrides
    )
    result = adjudications.call(
      InterpretationInput.adjudication(
        command_id: "cmd-adjudication-#{command_suffix}",
        source_message_id: message_id,
        interpretation_id:
      )
    )
    raise result.failure.inspect if result.failure?
  end

  def seed_proposal(
    interpretation_id:,
    message_id:,
    command_suffix: interpretation_id,
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
  end

  def decision_events(decision_id)
    event_store.read(streams.decision(decision_id), Coordinator::Write::EventQueries::DECISION_EXISTENCE)
  end

  def slot_events(slot_id)
    event_store.read(
      streams.decision_slot(slot_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[DecisionSlotOpened DecisionSlotHeadChanged],
        maximum_count: 2,
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

  def load(event)
    Coordinator::Write::EventSchemaRegistry.new.load(
      type: event.type,
      schema_version: event.metadata.fetch("schema_version"),
      data: event.data
    )
  end
end
