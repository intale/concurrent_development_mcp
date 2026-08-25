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
      ),
      Coordinator::Write::Events::WorkItemDependencySatisfiedV1.new(
        change_set_id: "CS-100",
        dependency_id: "DEP-1",
        producer_work_item_id: "W-100",
        consumer_work_item_id: "W-200",
        dependency_kind: "requires_candidate",
        required_output: nil,
        source_event: Coordinator::Write::EventReference.new(
          event_id: "0198c000-0000-7000-8000-000000000001",
          type: "WorkItemCandidateSelected",
          stream_context: "DevelopmentExecution",
          stream_name: "WorkItem",
          stream_id: "W-100",
          stream_revision: 3
        ),
        rule_version: "dependency-satisfaction/v1",
        satisfied_at: "2026-08-20T14:20:00.000000Z"
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
    expect(state).to be_dependency_satisfied("DEP-1")
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

  it "folds terminal completion without discarding the frozen graph" do
    reference = Coordinator::Write::EventReference.new(
      event_id: "0198c000-0000-7000-8000-000000000009",
      type: "WorkItemCompleted",
      stream_context: "DevelopmentExecution",
      stream_name: "WorkItem",
      stream_id: "W-100",
      stream_revision: 4
    )
    completion = Coordinator::Write::ChangeSetCompletions::WorkItemEvidenceV1.new(
      change_set_id: "CS-100",
      work_item_id: "W-100",
      repository_id: "billing",
      attempt_id: "A-100",
      candidate_id: "CAN-100",
      candidate_event: reference,
      selected_event: reference,
      completed_event: reference,
      completed_at: "2026-08-25T08:00:00.000000Z"
    )
    state = described_class.reduce([
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
      ),
      Coordinator::Write::Events::ChangeSetCompletedV1.new(
        change_set_id: "CS-100",
        work_item_completions: [ completion ],
        release_set_completion_event: nil,
        rule_version: "change-set-completion/v1",
        completed_at: "2026-08-25T08:00:00.000000Z"
      )
    ])

    expect(state).to have_attributes(
      status: "completed",
      completed_at: "2026-08-25T08:00:00.000000Z"
    )
  end
end
