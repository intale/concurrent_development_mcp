# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::ChangeSets::DeclareWorkItemDependency do
  subject(:decider) { described_class.new }

  let(:occurred_at) { "2026-08-20T14:14:00.000000Z" }
  let(:command) do
    Coordinator::Write::Commands::DeclareWorkItemDependency.new(
      command_id: "cmd-230",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "planner-1"),
      change_set_id: "CS-100",
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
      dependencies: []
    )
  end

  it "decides one dependency fact on the consumer WorkItem stream" do
    result = decider.call(state: draft_state, command:, occurred_at:)

    expect(result).to be_success
    write = result.value!.writes.sole
    expect(write.stream.to_h).to eq(
      context: "DevelopmentExecution", stream_name: "WorkItem", stream_id: "W-200"
    )
    expect(write.event).to eq(
      Coordinator::Write::Events::WorkItemDependencyDeclaredV2.new(
        change_set_id: "CS-100",
        dependency_id: "DEP-1",
        producer_work_item_id: "W-100",
        consumer_work_item_id: "W-200",
        dependency_kind: "requires_candidate",
        required_output: nil
      )
    )
  end

  it "accepts a required output only for dependency kinds that require one" do
    required_output = Coordinator::Write::RequiredOutput.new(kind: "artifact", key: "openapi-v1")
    valid = Coordinator::Write::Commands::DeclareWorkItemDependency.new(
      command.to_h.merge(
        dependency_kind: "requires_artifact",
        required_output:
      )
    )

    expect(decider.call(state: draft_state, command: valid, occurred_at:)).to be_success
  end

  it "rejects every modeled non-cycle denial without producing an event plan" do
    active = Coordinator::Write::Domain::ChangeSets::State.new(draft_state.to_h.merge(status: "active"))
    existing_dependency = Coordinator::Write::Domain::ChangeSets::Dependency.new(
      dependency_id: "DEP-1",
      producer_work_item_id: "W-100",
      consumer_work_item_id: "W-200",
      dependency_kind: "requires_candidate",
      required_output: nil
    )
    reused_id = Coordinator::Write::Domain::ChangeSets::State.new(
      draft_state.to_h.merge(dependencies: [ existing_dependency ])
    )
    at_limit = Coordinator::Write::Domain::ChangeSets::State.new(
      draft_state.to_h.merge(
        dependencies: Array.new(500) do |index|
          Coordinator::Write::Domain::ChangeSets::Dependency.new(
            dependency_id: "EXISTING-#{index}",
            producer_work_item_id: "W-100",
            consumer_work_item_id: "W-200",
            dependency_kind: "requires_candidate",
            required_output: nil
          )
        end
      )
    )
    missing_endpoint = Coordinator::Write::Commands::DeclareWorkItemDependency.new(
      command.to_h.merge(consumer_work_item_id: "W-missing")
    )
    self_reference = Coordinator::Write::Commands::DeclareWorkItemDependency.new(
      command.to_h.merge(consumer_work_item_id: "W-100")
    )
    missing_required_output = Coordinator::Write::Commands::DeclareWorkItemDependency.new(
      command.to_h.merge(dependency_kind: "requires_artifact")
    )
    unexpected_required_output = Coordinator::Write::Commands::DeclareWorkItemDependency.new(
      command.to_h.merge(required_output: Coordinator::Write::RequiredOutput.new(kind: "artifact", key: "schema"))
    )

    scenarios = [
      [ Coordinator::Write::Domain::ChangeSets::State.initial, command, :change_set_not_found ],
      [ active, command, :change_set_not_draft ],
      [ draft_state, missing_endpoint, :work_item_not_member ],
      [ draft_state, self_reference, :dependency_self_reference ],
      [ reused_id, command, :dependency_id_reused ],
      [ at_limit, command, :dependency_limit_reached ],
      [ draft_state, missing_required_output, :required_output_mismatch ],
      [ draft_state, unexpected_required_output, :required_output_mismatch ]
    ]

    aggregate_failures do
      scenarios.each do |state, current_command, expected_code|
        result = decider.call(state:, command: current_command, occurred_at:)

        expect(result).to be_failure
        expect(result.failure.code).to eq(expected_code)
      end
    end
  end

  it "rejects an edge when the existing graph reaches back to its producer" do
    reverse_path = Coordinator::Write::Domain::ChangeSets::Dependency.new(
      dependency_id: "DEP-existing",
      producer_work_item_id: "W-200",
      consumer_work_item_id: "W-100",
      dependency_kind: "requires_completion",
      required_output: nil
    )
    cyclic_state = Coordinator::Write::Domain::ChangeSets::State.new(
      draft_state.to_h.merge(dependencies: [ reverse_path ])
    )

    result = decider.call(state: cyclic_state, command:, occurred_at:)

    expect(result).to be_failure
    expect(result.failure.code).to eq(:dependency_cycle)
  end
end
