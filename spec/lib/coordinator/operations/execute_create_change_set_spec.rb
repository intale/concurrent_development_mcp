# frozen_string_literal: true

RSpec.describe Coordinator::Operations::ExecuteCreateChangeSet do
  let(:event_store) { FakeEventStore.new }
  let(:clock) { TestSupport::FixedClock.new("2026-08-20T14:10:00.000000Z") }
  let(:id_generator) { TestSupport::DeterministicIdGenerator.new }
  subject(:operation) do
    described_class.new(event_store:, clock:, id_generator:)
  end

  let(:input) do
    {
      command_id: "cmd-100",
      actor: { kind: "user", id: "user-1" },
      change_set_id: "CS-100",
      goal: "Add coordinated billing change",
      acceptance_criteria: [ "Two agents cannot own the same WorkItem" ]
    }
  end
  let(:streams) { Coordinator::StreamFactory.new }

  it "atomically persists the two decided facts and one durable completion" do
    result = operation.call(input)

    expect(result).to be_success
    expect(result.value!).to be_a(Coordinator::Events::CommandCompletedV1)
    expect(result.value!.command_id).to eq("cmd-100")
    expect(event_store.stream_events(streams.change_set("CS-100")).map(&:type)).to eq(
      [ "ChangeSetCreated", "ChangeSetAcceptanceCriteriaDefined" ]
    )
    expect(event_store.stream_events(streams.command("cmd-100")).map(&:type)).to eq([ "CommandCompleted" ])
    expect(event_store.multiple_calls).to eq(1)
  end

  it "replays the exact persisted result without appending facts" do
    original = operation.call(input)
    attempted_event_ids = event_store.attempted_event_ids.dup

    replay = operation.call(input)

    expect(replay).to be_success
    expect(replay.value!).to eq(original.value!)
    expect(event_store.attempted_event_ids).to eq(attempted_event_ids)
  end

  it "rejects reuse of a completed command ID with changed accepted input" do
    operation.call(input)

    result = operation.call(input.merge(goal: "A different goal"))

    expect(result).to be_failure
    expect(result.failure.code).to eq(:command_id_reused)
    expect(event_store.stream_events(streams.change_set("CS-100")).length).to eq(2)
    expect(event_store.stream_events(streams.command("cmd-100")).length).to eq(1)
  end

  it "returns a zero-event domain denial without completing the losing command" do
    operation.call(input)

    result = operation.call(input.merge(command_id: "cmd-101"))

    expect(result).to be_failure
    expect(result.failure.code).to eq(:change_set_already_exists)
    expect(event_store.stream_events(streams.command("cmd-101"))).to be_empty
  end

  it "rebuilds fresh events with stable IDs when the serializable block retries" do
    retrying_store = FakeEventStore.new(retry_once: true)
    retrying_operation = described_class.new(event_store: retrying_store, clock:, id_generator:)

    result = retrying_operation.call(input)

    expect(result).to be_success
    expect(retrying_store.attempted_event_ids.tally.values).to contain_exactly(2, 2, 2)
    expect(retrying_store.stream_events(streams.change_set("CS-100")).length).to eq(2)
    expect(retrying_store.stream_events(streams.command("cmd-100")).length).to eq(1)
  end

  it "rolls back domain facts when trusted completion construction raises" do
    completion_builder = instance_double(Coordinator::CommandCompletionBuilder)
    allow(completion_builder).to receive(:create_change_set).and_raise("receipt invariant failed")
    failing_operation = described_class.new(
      event_store:,
      clock:,
      id_generator:,
      completion_builder:
    )

    expect { failing_operation.call(input) }.to raise_error("receipt invariant failed")
    expect(event_store.stream_events(streams.change_set("CS-100"))).to be_empty
    expect(event_store.stream_events(streams.command("cmd-100"))).to be_empty
  end
end
