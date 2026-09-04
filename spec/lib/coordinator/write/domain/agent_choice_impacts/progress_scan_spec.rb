# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::AgentChoiceImpacts::ProgressScan do
  subject(:decider) { described_class.new }

  it "implements CHO-02-PAGE-01 by advancing after one full target page" do
    result = decider.call(
      state: running_state,
      command: progress_command(last_position: 550, count: 50, has_more: true)
    )

    expect(result).to be_success
    expect(result.value!.events.sole).to be_a(
      Coordinator::Write::Events::AgentChoiceImpactScanProgressedV2
    )
    expect(result.value!.events.sole).to have_attributes(
      next_from_position: 551,
      page_number: 1,
      from_position: 0,
      to_position: 900,
      page_size: 50
    )
  end

  it "implements CHO-02-PAGE-COMPLETE-01 including an empty final page" do
    state = running_state(from_position: 551, page_count: 1)
    result = decider.call(
      state:,
      command: progress_command(
        checkpoint: state.checkpoint_event,
        previous_from_position: 551,
        last_position: nil,
        count: 0,
        has_more: false
      )
    )

    expect(result).to be_success
    expect(result.value!.events.sole).to be_a(
      Coordinator::Write::Events::AgentChoiceImpactScanCompletedV2
    )
    expect(result.value!.events.sole).to have_attributes(scan_id:)
  end

  it "implements CHO-02-PAGE-STALE-01 as an explicit zero-event outcome" do
    result = decider.call(
      state: running_state(from_position: 551),
      command: progress_command(last_position: 550, count: 50, has_more: true)
    )

    expect(result.failure).to have_attributes(code: :agent_choice_impact_scan_checkpoint_changed)
  end

  it "rejects a page beyond the frozen source position" do
    result = decider.call(
      state: running_state,
      command: progress_command(last_position: 901, count: 1, has_more: false)
    )

    expect(result.failure).to have_attributes(code: :agent_choice_impact_scan_page_out_of_bounds)
  end

  it "rejects a sentinel claim when the processed page already reaches the frozen source position" do
    result = decider.call(
      state: running_state,
      command: progress_command(last_position: 900, count: 50, has_more: true)
    )

    expect(result.failure).to have_attributes(code: :agent_choice_impact_scan_page_out_of_bounds)
  end

  def progress_command(
    checkpoint: started_event,
    previous_from_position: 0,
    last_position:,
    count:,
    has_more:
  )
    Coordinator::Write::Commands::ProgressAgentChoiceImpactScan.new(
      command_id: "018f0000-0000-7000-8000-000000000003",
      actor: { kind: "system", id: "agent-choice-decision-impact" },
      scan_id:,
      expected_checkpoint: checkpoint,
      previous_from_position:,
      last_processed_position: last_position,
      page_choice_count: count,
      has_more:,
      policy_version: "agent-choice-decision-impact/v1"
    )
  end

  def running_state(
    from_position: 0,
    page_count: 0,
    checkpoint: started_event
  )
    Coordinator::Write::Domain::AgentChoiceImpacts::ScanState.new(
      status: "running",
      scan_id:,
      decision_change: decision_change,
      started_event:,
      checkpoint_event: checkpoint,
      from_position:,
      to_position: 900,
      page_size: 50,
      page_count:,
      policy_version: "agent-choice-decision-impact/v1",
      skip_reason: nil
    )
  end

  def decision_change
    Coordinator::Write::AgentChoiceImpacts::DecisionChangeEvidenceV2.new(
      source_event:,
      source_global_position: 900,
      source_command_id: "cmd-decision-change",
      source_actor: { kind: "orchestrator", id: "guidance-host" },
      decision_id: "D-impact",
      change_kind: "corrected",
      definition_digest: "sha256:#{'a' * 64}",
      retroactivity: "active_attempts",
      affected_partitions: [
        Coordinator::Write::Decisions::DecisionPartitionV1.new(
          partition_id: "repo:billing:testing",
          topic_root: "testing",
          anchor_kind: "repo",
          anchor_id: "billing"
        )
      ]
    )
  end

  def source_event
    @source_event ||= Coordinator::Write::EventReference.new(
      event_id: "018f0000-0000-7000-8000-000000000001",
      type: "DecisionDefinitionCorrected",
      stream_context: "HumanGuidance",
      stream_name: "Decision",
      stream_id: "D-impact",
      stream_revision: 2
    )
  end

  def started_event
    @started_event ||= Coordinator::Write::EventReference.new(
      event_id: "018f0000-0000-7000-8000-000000000002",
      type: "AgentChoiceImpactScanStarted",
      stream_context: "AgentGovernance",
      stream_name: "AgentChoiceImpactScan",
      stream_id: scan_id,
      stream_revision: 0
    )
  end

  def scan_id
    "018f0000-0000-7000-8000-000000000004"
  end

end
