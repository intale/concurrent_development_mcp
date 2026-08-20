# frozen_string_literal: true

RSpec.describe Coordinator::Domain::ChangeSets::Create do
  subject(:decider) { described_class.new }

  let(:command) do
    Coordinator::Commands::CreateChangeSet.new(
      command_id: "cmd-100",
      actor: Coordinator::Commands::Actor.new(kind: "user", id: "user-1"),
      change_set_id: "CS-100",
      goal: "Add coordinated billing change",
      acceptance_criteria: [ "Two agents cannot own the same WorkItem" ]
    )
  end
  let(:occurred_at) { "2026-08-20T14:10:00.000000Z" }

  it "implements PLN-01-SUCCESS-01 as one ordered event plan" do
    result = decider.call(
      state: Coordinator::Domain::ChangeSets::State.initial,
      command:,
      occurred_at:
    )

    expect(result).to be_success
    expect(result.value!.events).to contain_exactly(
      an_instance_of(Coordinator::Events::ChangeSetCreatedV1),
      an_instance_of(Coordinator::Events::ChangeSetAcceptanceCriteriaDefinedV1)
    )
    expect(result.value!.events.map { _1.class.event_type }).to eq(
      [ "ChangeSetCreated", "ChangeSetAcceptanceCriteriaDefined" ]
    )
    expect(result.value!.writes.map(&:stream).map(&:to_h)).to eq(
      [
        { context: "DevelopmentPlanning", stream_name: "ChangeSet", stream_id: "CS-100" },
        { context: "DevelopmentPlanning", stream_name: "ChangeSet", stream_id: "CS-100" }
      ]
    )
    expect(result.value!.events.map(&:to_h)).to eq(
      [
        {
          change_set_id: "CS-100",
          goal: "Add coordinated billing change",
          created_at: occurred_at
        },
        {
          change_set_id: "CS-100",
          acceptance_criteria: [ "Two agents cannot own the same WorkItem" ],
          defined_at: occurred_at
        }
      ]
    )
  end

  it "implements PLN-01-DUPLICATE-ID-01 as an explicit zero-event failure" do
    prior_events = decider.call(
      state: Coordinator::Domain::ChangeSets::State.initial,
      command:,
      occurred_at:
    ).value!.events
    state = Coordinator::Domain::ChangeSets::State.reduce(prior_events)

    result = decider.call(state:, command:, occurred_at:)

    expect(result).to be_failure
    expect(result.failure.code).to eq(:change_set_already_exists)
    expect(result.failure.details).to eq(change_set_id: "CS-100")
  end

  it "keeps commands, events, and reduced state deeply immutable" do
    plan = decider.call(
      state: Coordinator::Domain::ChangeSets::State.initial,
      command:,
      occurred_at:
    ).value!
    state = Coordinator::Domain::ChangeSets::State.reduce(plan.events)

    expect(command).to be_frozen
    expect(command.acceptance_criteria).to be_frozen
    expect(command.acceptance_criteria.first).to be_frozen
    expect(plan.events).to be_frozen
    expect(plan.events).to all(be_frozen)
    expect(plan.writes).to be_frozen
    expect(plan.writes).to all(be_frozen)
    expect(plan.writes.map(&:stream)).to all(be_frozen)
    expect(state).to be_frozen
    expect(state.acceptance_criteria).to be_frozen
  end
end
