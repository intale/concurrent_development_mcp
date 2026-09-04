# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::ChangeSets::Activate do
  subject(:decider) { described_class.new }

  let(:occurred_at) { "2026-08-20T14:15:00.000000Z" }
  let(:command) do
    Coordinator::Write::Commands::ActivateChangeSet.new(
      command_id: "cmd-250",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "planner-1"),
      change_set_id: "CS-100"
    )
  end
  let(:dependency) do
    Coordinator::Write::Domain::ChangeSets::Dependency.new(
      dependency_id: "DEP-1",
      producer_work_item_id: "W-100",
      consumer_work_item_id: "W-200",
      dependency_kind: "requires_candidate",
      required_output: nil
    )
  end
  let(:draft_state) do
    Coordinator::Write::Domain::ChangeSets::State.new(
      change_set_id: "CS-100",
      goal: "Coordinate billing changes",
      status: "draft",
      acceptance_criteria: [ "Agents do not overlap" ],
      work_item_ids: [ "W-100", "W-200" ],
      dependencies: [ dependency ]
    )
  end

  it "implements PLN-ACTIVATE-SUCCESS-01 as a lifecycle fact without a graph snapshot" do
    result = decider.call(state: draft_state, command:, occurred_at:)

    expect(result).to be_success
    write = result.value!.writes.sole
    expect(write.stream.to_h).to eq(
      context: "DevelopmentPlanning",
      stream_name: "ChangeSet",
      stream_id: "CS-100"
    )
    expect(write.event).to eq(
      Coordinator::Write::Events::ChangeSetActivatedV2.new(change_set_id: "CS-100")
    )
  end

  it "returns every modeled non-cycle denial without an event plan" do
    active = Coordinator::Write::Domain::ChangeSets::State.new(draft_state.to_h.merge(status: "active"))
    no_criteria = Coordinator::Write::Domain::ChangeSets::State.new(
      draft_state.to_h.merge(acceptance_criteria: [])
    )
    no_work_items = Coordinator::Write::Domain::ChangeSets::State.new(
      draft_state.to_h.merge(work_item_ids: [], dependencies: [])
    )
    missing_endpoint = Coordinator::Write::Domain::ChangeSets::State.new(
      draft_state.to_h.merge(work_item_ids: [ "W-100" ])
    )

    scenarios = [
      [ Coordinator::Write::Domain::ChangeSets::State.initial, :change_set_not_found ],
      [ active, :change_set_already_active ],
      [ no_criteria, :change_set_has_no_criteria ],
      [ no_work_items, :change_set_has_no_work_items ],
      [ missing_endpoint, :dependency_endpoint_missing ]
    ]

    aggregate_failures do
      scenarios.each do |state, expected_code|
        result = decider.call(state:, command:, occurred_at:)

        expect(result).to be_failure
        expect(result.failure.code).to eq(expected_code)
      end
    end
  end

  it "rejects a cycle found in the complete authoritative graph" do
    reverse = Coordinator::Write::Domain::ChangeSets::Dependency.new(
      dependency_id: "DEP-2",
      producer_work_item_id: "W-200",
      consumer_work_item_id: "W-100",
      dependency_kind: "requires_completion",
      required_output: nil
    )
    cyclic = Coordinator::Write::Domain::ChangeSets::State.new(
      draft_state.to_h.merge(dependencies: [ dependency, reverse ])
    )

    result = decider.call(state: cyclic, command:, occurred_at:)

    expect(result).to be_failure
    expect(result.failure.code).to eq(:dependency_cycle)
  end
end
