# frozen_string_literal: true

RSpec.describe Coordinator::Domain::ChangeSets::State do
  it "folds membership and the typed dependency graph from authoritative facts" do
    events = [
      Coordinator::Events::ChangeSetCreatedV1.new(
        change_set_id: "CS-100",
        goal: "Coordinate billing changes",
        created_at: "2026-08-20T14:10:00.000000Z"
      ),
      Coordinator::Events::WorkItemAddedToChangeSetV1.new(
        change_set_id: "CS-100",
        work_item_id: "W-100",
        added_at: "2026-08-20T14:12:00.000000Z"
      ),
      Coordinator::Events::WorkItemAddedToChangeSetV1.new(
        change_set_id: "CS-100",
        work_item_id: "W-200",
        added_at: "2026-08-20T14:13:00.000000Z"
      ),
      Coordinator::Events::WorkItemDependencyDeclaredV1.new(
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
      Coordinator::Domain::ChangeSets::Dependency.new(
        dependency_id: "DEP-1",
        producer_work_item_id: "W-100",
        consumer_work_item_id: "W-200",
        dependency_kind: "requires_candidate",
        required_output: nil
      )
    )
  end
end
