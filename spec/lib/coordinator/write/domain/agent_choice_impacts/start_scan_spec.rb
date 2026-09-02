# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::AgentChoiceImpacts::StartScan do
  subject(:decider) { described_class.new }

  it "implements CHO-02-START-01 by starting a bounded active-Attempt scan" do
    result = decider.call(
      state: Coordinator::Write::Domain::AgentChoiceImpacts::ScanState.initial,
      command: start_command,
      decision_change: decision_change("active_attempts"),
      started_at: occurred_at
    )

    expect(result).to be_success
    expect(result.value!.writes.sole).to have_attributes(
      stream: streams.agent_choice_impact_scan(scan_id),
      event: have_attributes(
        scan_id:,
        from_position: 0,
        to_position: 900,
        page_size: 50,
        policy_version: "agent-choice-decision-impact/v1",
        started_at: occurred_at
      )
    )
    expect(result.value!.events.sole).to be_a(
      Coordinator::Write::Events::AgentChoiceImpactScanStartedV1
    )
  end

  it "implements CHO-02-START-SKIP-01 with explicit target-specific skip reasons" do
    reasons = {
      "future_only" => "future_only",
      "all_unverified_candidates" => "candidate_scope",
      "all_unmerged_candidates" => "candidate_scope",
      "all_artifacts" => "artifact_scope"
    }

    reasons.each do |retroactivity, reason|
      result = decider.call(
        state: Coordinator::Write::Domain::AgentChoiceImpacts::ScanState.initial,
        command: start_command,
        decision_change: decision_change(retroactivity),
        started_at: occurred_at
      )

      expect(result.value!.events.sole).to have_attributes(
        reason:,
        decision_change: have_attributes(retroactivity:)
      )
    end
  end

  it "implements CHO-02-START-REPLAY-01 as an explicit zero-event outcome" do
    result = decider.call(
      state: running_state,
      command: start_command,
      decision_change: decision_change("active_attempts"),
      started_at: occurred_at
    )

    expect(result.failure).to have_attributes(code: :agent_choice_impact_scan_already_decided)
  end

  def start_command
    Coordinator::Write::Commands::StartAgentChoiceImpactScan.new(
      command_id: scan_id,
      actor: { kind: "system", id: "agent-choice-decision-impact" },
      scan_id:,
      source_event:,
      source_global_position: 900,
      policy_version: "agent-choice-decision-impact/v1"
    )
  end

  def decision_change(retroactivity)
    Coordinator::Write::AgentChoiceImpacts::DecisionChangeEvidenceV1.new(
      source_event:,
      source_global_position: 900,
      source_command_id: "cmd-decision-change",
      source_actor: { kind: "orchestrator", id: "guidance-host" },
      decision_id: "D-impact",
      change_kind: "corrected",
      definition_digest: "sha256:#{'a' * 64}",
      retroactivity:,
      affected_partitions: [ partition ],
      changed_at: occurred_at
    )
  end

  def running_state
    Coordinator::Write::Domain::AgentChoiceImpacts::ScanState.new(
      status: "running",
      scan_id:,
      decision_change: decision_change("active_attempts"),
      started_event: checkpoint,
      checkpoint_event: checkpoint,
      from_position: 0,
      to_position: 900,
      page_size: 50,
      page_count: 0,
      total_choice_count: 0,
      policy_version: "agent-choice-decision-impact/v1",
      skip_reason: nil
    )
  end

  def partition
    Coordinator::Write::Decisions::DecisionPartitionV1.new(
      partition_id: "repo:billing:testing",
      topic_root: "testing",
      anchor_kind: "repo",
      anchor_id: "billing"
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

  def checkpoint
    @checkpoint ||= Coordinator::Write::EventReference.new(
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

  def streams
    @streams ||= Coordinator::Write::StreamFactory.new
  end

  def occurred_at
    "2026-08-23T08:00:00.000000Z"
  end
end
