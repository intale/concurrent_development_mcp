# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::WorkItems::Create do
  subject(:decider) { described_class.new }

  let(:command) do
    Coordinator::Write::Commands::CreateWorkItem.new(
      command_id: "cmd-200",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "planner-1"),
      change_set_id: "CS-100",
      work_item_id: "W-200",
      repository_id: "billing",
      goal: "Implement capture validation",
      acceptance_criteria: [ "Reject duplicate ownership" ]
    )
  end
  let(:occurred_at) { "2026-08-20T14:12:00.000000Z" }
  let(:draft_change_set) do
    Coordinator::Write::Domain::ChangeSets::State.new(
      change_set_id: "CS-100",
      goal: "Coordinate billing changes",
      status: "draft",
      acceptance_criteria: [ "Agents do not overlap" ],
      work_item_ids: [],
      dependencies: []
    )
  end

  it "implements PLN-02-SUCCESS-01 as one ordered cross-stream event plan" do
    result = decider.call(
      change_set_state: draft_change_set,
      work_item_state: Coordinator::Write::Domain::WorkItems::State.initial,
      command:,
      occurred_at:
    )

    expect(result).to be_success
    plan = result.value!
    expect(plan.writes.map { _1.stream.to_h }).to eq(
      [
        { context: "DevelopmentExecution", stream_name: "WorkItem", stream_id: "W-200" },
        { context: "DevelopmentPlanning", stream_name: "ChangeSet", stream_id: "CS-100" }
      ]
    )
    expect(plan.events).to contain_exactly(
      Coordinator::Write::Events::WorkItemCreatedV1.new(
        work_item_id: "W-200",
        change_set_id: "CS-100",
        repository_id: "billing",
        goal: "Implement capture validation",
        acceptance_criteria: [ "Reject duplicate ownership" ],
        competitive_mode: false,
        created_at: occurred_at
      ),
      Coordinator::Write::Events::WorkItemAddedToChangeSetV1.new(
        change_set_id: "CS-100",
        work_item_id: "W-200",
        added_at: occurred_at
      )
    )
  end

  it "returns zero-event denials for each modeled Given that forbids creation" do
    active_change_set = Coordinator::Write::Domain::ChangeSets::State.new(draft_change_set.to_h.merge(status: "active"))
    full_change_set = Coordinator::Write::Domain::ChangeSets::State.new(
      draft_change_set.to_h.merge(work_item_ids: Array.new(100) { |index| "W-#{index}" })
    )
    existing_work_item = Coordinator::Write::Domain::WorkItems::State.new(
      work_item_id: "W-200",
      change_set_id: "CS-100",
      repository_id: "billing",
      goal: "Existing work",
      acceptance_criteria: [ "Already planned" ],
      status: "planned"
    )

    scenarios = [
      [ Coordinator::Write::Domain::ChangeSets::State.initial, Coordinator::Write::Domain::WorkItems::State.initial, :change_set_not_found ],
      [ active_change_set, Coordinator::Write::Domain::WorkItems::State.initial, :change_set_not_draft ],
      [ draft_change_set, existing_work_item, :work_item_already_exists ],
      [ full_change_set, Coordinator::Write::Domain::WorkItems::State.initial, :work_item_limit_reached ]
    ]

    aggregate_failures do
      scenarios.each do |change_set_state, work_item_state, expected_code|
        result = decider.call(change_set_state:, work_item_state:, command:, occurred_at:)

        expect(result).to be_failure
        expect(result.failure.code).to eq(expected_code)
      end
    end
  end
end
