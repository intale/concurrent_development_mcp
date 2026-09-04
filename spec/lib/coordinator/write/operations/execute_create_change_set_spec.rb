# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteCreateChangeSet, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:change_set_events) do
    Coordinator::Write::EventReadCriteria.new(
      event_types: [ "ChangeSetCreated", "ChangeSetGoalDefined", "ChangeSetAcceptanceCriteriaDefined" ],
      maximum_count: 3,
      direction: :asc
    )
  end
  let(:command_events) do
    Coordinator::Write::EventQueries::COMMAND_HISTORY
  end
  subject(:operation) { described_class.new(event_store:) }

  let(:input) do
    {
      command_id: "cmd-100",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-100",
      goal: "Coordinate billing changes",
      acceptance_criteria: [ "Agents do not overlap" ]
    }
  end

  it "persists cohesive identity, goal, and acceptance-criteria facts" do
    result = operation.call(input)

    expect(result).to be_success
    completion = result.value!
    facts = event_store.read(streams.change_set("CS-100"), change_set_events)
    expect(facts.map(&:type)).to eq(
      [ "ChangeSetCreated", "ChangeSetGoalDefined", "ChangeSetAcceptanceCriteriaDefined" ]
    )
    expect(facts.map(&:stream_revision)).to eq([ 0, 1, 2 ])
    expect(facts.map(&:id)).to all(match(Coordinator::Shared::Types::UUID_V7_PATTERN))
    expect(facts.first.data).to eq("change_set_id" => "CS-100")
    expect(facts.first.created_at.utc.iso8601(6)).to match(Coordinator::Shared::Types::TIMESTAMP_PATTERN)
    expect(event_store.read(streams.command("cmd-100"), command_events)).to be_empty
    expect(completion.data).to eq(
      Coordinator::Write::CommandReceiptData::ChangeSet.new(change_set_id: "CS-100")
    )
  end

  it "leaves replay ownership to the registered Command lifecycle" do
    expect(operation.call(input)).to be_success
    original_ids = persisted_ids

    replay = operation.call(input)

    expect(replay.failure.code).to eq(:change_set_already_exists)
    expect(persisted_ids).to eq(original_ids)
  end

  it "enforces the entity invariant independently of public request identity" do
    operation.call(input)

    result = operation.call(input.merge(goal: "A different goal"))

    expect(result).to be_failure
    expect(result.failure.code).to eq(:change_set_already_exists)
    expect(event_store.read(streams.command("cmd-100"), command_events)).to be_empty
  end

  it "returns a zero-event duplicate denial without completing the losing command" do
    operation.call(input)

    result = operation.call(input.merge(command_id: "cmd-101"))

    expect(result).to be_failure
    expect(result.failure.code).to eq(:change_set_already_exists)
    expect(event_store.read(streams.command("cmd-101"), command_events)).to be_empty
  end

  it "serializes concurrent real commands so exactly one creates the ChangeSet" do
    competing_inputs = [
      input.merge(command_id: "cmd-concurrent-1"),
      input.merge(command_id: "cmd-concurrent-2")
    ]

    results = competing_inputs.map do |competing_input|
      Thread.new { described_class.new(event_store:).call(competing_input) }
    end.map(&:value)

    expect(results.count(&:success?)).to eq(1)
    expect(results.count(&:failure?)).to eq(1)
    expect(results.find(&:failure?).failure.code).to eq(:change_set_already_exists)
    expect(event_store.read(streams.change_set("CS-100"), change_set_events).map(&:type)).to eq(
      [ "ChangeSetCreated", "ChangeSetGoalDefined", "ChangeSetAcceptanceCriteriaDefined" ]
    )
    completed_commands = competing_inputs.count do |competing_input|
      event_store.read(streams.command(competing_input.fetch(:command_id)), command_events).one?
    end
    expect(completed_commands).to eq(0)
  end

  def persisted_ids
    event_store.read(streams.change_set("CS-100"), change_set_events).map(&:id) +
      event_store.read(streams.command("cmd-100"), command_events).map(&:id)
  end
end
