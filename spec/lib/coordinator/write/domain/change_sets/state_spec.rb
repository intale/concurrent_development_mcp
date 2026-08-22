# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::ChangeSets::State do
  it "folds membership and the typed dependency graph from authoritative facts" do
    events = [
      Coordinator::Write::Events::ChangeSetCreatedV1.new(
        change_set_id: "CS-100",
        goal: "Coordinate billing changes",
        created_at: "2026-08-20T14:10:00.000000Z"
      ),
      Coordinator::Write::Events::WorkItemAddedToChangeSetV1.new(
        change_set_id: "CS-100",
        work_item_id: "W-100",
        added_at: "2026-08-20T14:12:00.000000Z"
      ),
      Coordinator::Write::Events::WorkItemAddedToChangeSetV1.new(
        change_set_id: "CS-100",
        work_item_id: "W-200",
        added_at: "2026-08-20T14:13:00.000000Z"
      ),
      Coordinator::Write::Events::WorkItemDependencyDeclaredV1.new(
        change_set_id: "CS-100",
        dependency_id: "DEP-1",
        producer_work_item_id: "W-100",
        consumer_work_item_id: "W-200",
        dependency_kind: "requires_candidate",
        required_output: nil,
        declared_at: "2026-08-20T14:14:00.000000Z"
      )
    ]

    state = described_class.reduce(events)

    expect(state.work_item_ids).to eq([ "W-100", "W-200" ])
    expect(state.dependencies).to contain_exactly(
      Coordinator::Write::Domain::ChangeSets::Dependency.new(
        dependency_id: "DEP-1",
        producer_work_item_id: "W-100",
        consumer_work_item_id: "W-200",
        dependency_kind: "requires_candidate",
        required_output: nil
      )
    )
  end

  it "folds activation as the boundary that closes structural planning" do
    state = described_class.reduce(
      [
        Coordinator::Write::Events::ChangeSetCreatedV1.new(
          change_set_id: "CS-100",
          goal: "Coordinate billing changes",
          created_at: "2026-08-20T14:10:00.000000Z"
        ),
        Coordinator::Write::Events::ChangeSetActivatedV1.new(
          change_set_id: "CS-100",
          work_item_count: 1,
          dependency_count: 0,
          activated_at: "2026-08-20T14:15:00.000000Z"
        )
      ]
    )

    expect(state.status).to eq("active")
  end
end
