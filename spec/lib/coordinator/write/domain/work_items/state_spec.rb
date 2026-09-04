# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::WorkItems::State do
  let(:work_item_created) do
    Coordinator::Write::Events::WorkItemCreatedV1.new(
      work_item_id: "W-200",
      change_set_id: "CS-100",
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      goal: "Implement capture validation",
      acceptance_criteria: [ "Reject duplicate ownership" ],
      competitive_mode: false,
      created_at: "2026-08-20T14:12:00.000000Z"
    )
  end

  it "folds WorkItemCreated into the authoritative planned state" do
    state = described_class.reduce([ work_item_created ])

    expect(state.to_h).to eq(
      work_item_id: "W-200",
      change_set_id: "CS-100",
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      goal: "Implement capture validation",
      acceptance_criteria: [ "Reject duplicate ownership" ],
      competitive_mode: false,
      status: "planned",
      active_attempt_id: nil,
      active_agent_id: nil,
      selected_candidate_id: nil,
      selected_candidate_event: nil,
      produced_outputs: [],
      completed_at: nil
    )
    expect(state).to be_frozen
  end

  it "applies WorkItemMadeReady to the authoritative lifecycle state" do
    planned = described_class.reduce([ work_item_created ])
    made_ready = Coordinator::Write::Events::WorkItemMadeReadyV1.new(
      change_set_id: "CS-100",
      work_item_id: "W-200",
      readiness_decision_id: "readiness-v1:#{"a" * 64}",
      reason: "change_set_activated",
      made_ready_at: "2026-08-20T14:15:01.000000Z"
    )

    ready = planned.apply(made_ready)

    expect(ready.status).to eq("ready")
    expect(ready.work_item_id).to eq("W-200")
    expect(ready.repository_id).to eq(RepositoryScenario::DEFAULT_REPOSITORY_ID)
  end

  it "applies WorkItemAcquired as authoritative active ownership" do
    ready = described_class.reduce([ work_item_created ]).apply(
      Coordinator::Write::Events::WorkItemMadeReadyV1.new(
        change_set_id: "CS-100",
        work_item_id: "W-200",
        readiness_decision_id: "readiness-v1:#{"a" * 64}",
        reason: "change_set_activated",
        made_ready_at: "2026-08-20T14:15:01.000000Z"
      )
    )
    acquired = ready.apply(
      Coordinator::Write::Events::WorkItemAcquiredV1.new(
        change_set_id: "CS-100",
        work_item_id: "W-200",
        attempt_id: "A-300",
        agent_id: "agent-a",
        acquired_at: "2026-08-20T14:20:00.000000Z"
      )
    )

    expect(acquired.status).to eq("active")
    expect(acquired.active_attempt_id).to eq("A-300")
    expect(acquired.active_agent_id).to eq("agent-a")
  end

  it "folds Candidate selection and completion into terminal state" do
    candidate_event = Coordinator::Write::EventReference.new(
      event_id: "01919191-9191-7191-8191-919191919191",
      type: "CandidateSubmitted",
      stream_context: "DevelopmentIntegration",
      stream_name: "Candidate",
      stream_id: "CAN-400",
      stream_revision: 0
    )
    outputs = [
      Coordinator::Write::WorkItemOutputV1.new(kind: "artifact", key: "billing-gem")
    ]
    events = [
      work_item_created,
      Coordinator::Write::Events::WorkItemMadeReadyV1.new(
        change_set_id: "CS-100",
        work_item_id: "W-200",
        readiness_decision_id: "readiness-v1:#{"a" * 64}",
        reason: "change_set_activated",
        made_ready_at: "2026-08-20T14:15:01.000000Z"
      ),
      Coordinator::Write::Events::WorkItemAcquiredV1.new(
        change_set_id: "CS-100",
        work_item_id: "W-200",
        attempt_id: "A-300",
        agent_id: "agent-a",
        acquired_at: "2026-08-20T14:20:00.000000Z"
      ),
      Coordinator::Write::Events::WorkItemCandidateSelectedV1.new(
        change_set_id: "CS-100",
        work_item_id: "W-200",
        attempt_id: "A-300",
        candidate_id: "CAN-400",
        candidate_event:,
        selected_at: "2026-08-20T14:30:00.000000Z"
      ),
      Coordinator::Write::Events::WorkItemCompletedV1.new(
        change_set_id: "CS-100",
        work_item_id: "W-200",
        attempt_id: "A-300",
        candidate_id: "CAN-400",
        candidate_event:,
        produced_outputs: outputs,
        rule_version: "work-item-completion/v1",
        completed_at: "2026-08-20T14:30:00.000000Z"
      )
    ]

    state = described_class.reduce(events)

    expect(state).to have_attributes(
      status: "completed",
      selected_candidate_id: "CAN-400",
      selected_candidate_event: candidate_event,
      produced_outputs: outputs,
      completed_at: "2026-08-20T14:30:00.000000Z"
    )
  end
end
