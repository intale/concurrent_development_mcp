# frozen_string_literal: true

RSpec.describe Coordinator::Domain::WorkItems::State do
  let(:work_item_created) do
    Coordinator::Events::WorkItemCreatedV1.new(
      work_item_id: "W-200",
      change_set_id: "CS-100",
      repository_id: "billing",
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
      repository_id: "billing",
      goal: "Implement capture validation",
      acceptance_criteria: [ "Reject duplicate ownership" ],
      status: "planned"
    )
    expect(state).to be_frozen
  end

  it "applies WorkItemMadeReady to the authoritative lifecycle state" do
    planned = described_class.reduce([ work_item_created ])
    made_ready = Coordinator::Events::WorkItemMadeReadyV1.new(
      change_set_id: "CS-100",
      work_item_id: "W-200",
      readiness_decision_id: "readiness-v1:#{"a" * 64}",
      reason: "change_set_activated",
      made_ready_at: "2026-08-20T14:15:01.000000Z"
    )

    ready = planned.apply(made_ready)

    expect(ready.status).to eq("ready")
    expect(ready.work_item_id).to eq("W-200")
    expect(ready.repository_id).to eq("billing")
  end
end
