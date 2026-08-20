# frozen_string_literal: true

RSpec.describe Coordinator::Operations::ExecuteCreateChangeSet, :event_store do
  let(:event_store) { Coordinator::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::StreamFactory.new }
  let(:change_set_events) do
    Coordinator::EventReadCriteria.new(
      event_types: [ "ChangeSetCreated", "ChangeSetAcceptanceCriteriaDefined" ],
      maximum_count: 2,
      direction: :asc
    )
  end
  let(:command_events) do
    Coordinator::EventReadCriteria.new(
      event_types: [ "CommandCompleted" ],
      maximum_count: 1,
      direction: :asc
    )
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

  it "persists the two facts and durable typed receipt through the real store" do
    result = operation.call(input)

    expect(result).to be_success
    completion = result.value!
    facts = event_store.read(streams.change_set("CS-100"), change_set_events)
    expect(facts.map(&:type)).to eq(
      [ "ChangeSetCreated", "ChangeSetAcceptanceCriteriaDefined" ]
    )
    expect(facts.map(&:stream_revision)).to eq([ 0, 1 ])
    expect(facts.map(&:id)).to all(match(Coordinator::Types::UUID_V7_PATTERN))
    expect(facts.first.data.fetch("created_at")).to match(Coordinator::Types::TIMESTAMP_PATTERN)
    expect(event_store.read(streams.command("cmd-100"), command_events).map(&:type)).to eq([ "CommandCompleted" ])
    expect(completion.data).to eq(
      Coordinator::CommandReceiptData::ChangeSet.new(change_set_id: "CS-100")
    )
  end

  it "replays the exact persisted completion without another real append" do
    original = operation.call(input)
    original_ids = persisted_ids

    replay = operation.call(input)

    expect(replay).to be_success
    expect(replay.value!).to eq(original.value!)
    expect(persisted_ids).to eq(original_ids)
  end

  it "rejects reuse of a completed command ID with changed accepted input" do
    operation.call(input)

    result = operation.call(input.merge(goal: "A different goal"))

    expect(result).to be_failure
    expect(result.failure.code).to eq(:command_id_reused)
    expect(event_store.read(streams.command("cmd-100"), command_events).length).to eq(1)
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
      [ "ChangeSetCreated", "ChangeSetAcceptanceCriteriaDefined" ]
    )
    completed_commands = competing_inputs.count do |competing_input|
      event_store.read(streams.command(competing_input.fetch(:command_id)), command_events).one?
    end
    expect(completed_commands).to eq(1)
  end

  def persisted_ids
    event_store.read(streams.change_set("CS-100"), change_set_events).map(&:id) +
      event_store.read(streams.command("cmd-100"), command_events).map(&:id)
  end
end
