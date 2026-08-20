# frozen_string_literal: true

RSpec.describe Coordinator::Domain::WorkItems::State do
  it "folds WorkItemCreated into the authoritative planned state" do
    event = Coordinator::Events::WorkItemCreatedV1.new(
      work_item_id: "W-200",
      change_set_id: "CS-100",
      repository_id: "billing",
      goal: "Implement capture validation",
      acceptance_criteria: [ "Reject duplicate ownership" ],
      competitive_mode: false,
      created_at: "2026-08-20T14:12:00.000000Z"
    )

    state = described_class.reduce([ event ])

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
end
