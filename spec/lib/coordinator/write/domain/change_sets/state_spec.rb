# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::ChangeSets::State do
  let(:definition) do
    [
      Coordinator::Write::Events::ChangeSetCreatedV2.new(change_set_id: "CS-100"),
      Coordinator::Write::Events::ChangeSetGoalDefinedV1.new(
        change_set_id: "CS-100", goal: "Coordinate billing changes"
      ),
      Coordinator::Write::Events::WorkItemAddedToChangeSetV2.new(
        change_set_id: "CS-100", work_item_id: "W-100"
      ),
      Coordinator::Write::Events::WorkItemAddedToChangeSetV2.new(
        change_set_id: "CS-100", work_item_id: "W-200"
      )
    ]
  end

  it "folds membership and the typed dependency graph from authoritative facts" do
    source = Coordinator::Write::EventReference.new(
      event_id: SecureRandom.uuid_v7,
      type: "WorkItemCandidateSelected",
      stream_context: "DevelopmentExecution",
      stream_name: "WorkItem",
      stream_id: "W-100",
      stream_revision: 3
    )
    dependency = {
      change_set_id: "CS-100",
      dependency_id: "DEP-1",
      producer_work_item_id: "W-100",
      consumer_work_item_id: "W-200",
      dependency_kind: "requires_candidate",
      required_output: nil
    }
    state = described_class.reduce([
      *definition,
      Coordinator::Write::Events::WorkItemDependencyDeclaredV2.new(dependency),
      Coordinator::Write::Events::WorkItemDependencySatisfiedV2.new(dependency.merge(source:))
    ])

    expect(state).to have_attributes(goal: "Coordinate billing changes", work_item_ids: [ "W-100", "W-200" ])
    expect(state.dependencies).to contain_exactly(
      Coordinator::Write::Domain::ChangeSets::Dependency.new(dependency.except(:change_set_id))
    )
    expect(state).to be_dependency_satisfied("DEP-1")
  end

  it "folds activation as the boundary that closes structural planning" do
    state = described_class.reduce([
      *definition,
      Coordinator::Write::Events::ChangeSetActivatedV2.new(change_set_id: "CS-100")
    ])

    expect(state.status).to eq("active")
  end

  it "folds the lean terminal fact without discarding the frozen graph" do
    state = described_class.reduce([
      *definition,
      Coordinator::Write::Events::ChangeSetActivatedV2.new(change_set_id: "CS-100"),
      Coordinator::Write::Events::ChangeSetCompletedV2.new(change_set_id: "CS-100")
    ])

    expect(state).to have_attributes(status: "completed", work_item_ids: [ "W-100", "W-200" ])
  end
end
