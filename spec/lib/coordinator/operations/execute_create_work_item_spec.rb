# frozen_string_literal: true

RSpec.describe Coordinator::Operations::ExecuteCreateWorkItem do
  let(:event_store) { FakeEventStore.new }
  let(:clock) { TestSupport::FixedClock.new("2026-08-20T14:12:00.000000Z") }
  let(:id_generator) { TestSupport::DeterministicIdGenerator.new }
  let(:streams) { Coordinator::StreamFactory.new }
  subject(:operation) do
    described_class.new(event_store:, clock:, id_generator:)
  end

  let(:input) do
    {
      command_id: "cmd-200",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-100",
      work_item_id: "W-200",
      repository_id: "billing",
      goal: "Implement capture validation",
      acceptance_criteria: [ "Reject duplicate ownership" ]
    }
  end

  before do
    seed_change_set(event_store)
  end

  it "atomically persists both cross-stream facts and the durable completion" do
    result = operation.call(input)

    expect(result).to be_success
    completion = result.value!
    expect(completion).to be_a(Coordinator::Events::CommandCompletedV1)
    expect(completion.data).to eq(
      Coordinator::CommandReceiptData::WorkItem.new(
        change_set_id: "CS-100",
        work_item_id: "W-200"
      )
    )
    expect(event_store.stream_events(streams.work_item("W-200")).map(&:type)).to eq([ "WorkItemCreated" ])
    expect(event_store.stream_events(streams.change_set("CS-100")).map(&:type)).to eq(
      [ "ChangeSetCreated", "ChangeSetAcceptanceCriteriaDefined", "WorkItemAddedToChangeSet" ]
    )
    expect(event_store.stream_events(streams.command("cmd-200")).map(&:type)).to eq([ "CommandCompleted" ])
    expect(completion.projection_barriers.coord_context_v1.map(&:to_h)).to contain_exactly(
      hash_including(stream_name: "WorkItem", stream_revision: 0),
      hash_including(stream_name: "ChangeSet", stream_revision: 2)
    )
    expect(event_store.multiple_calls).to eq(1)
  end

  it "writes the frozen routing markers without using them as domain state" do
    operation.call(input)

    created = event_store.stream_events(streams.work_item("W-200")).sole
    membership = event_store.stream_events(streams.change_set("CS-100")).last
    expect(created.markers).to eq(
      [ "change-set:CS-100", "command:cmd-200", "repository:billing", "work-item:W-200" ]
    )
    expect(membership.markers).to eq(
      [ "change-set:CS-100", "command:cmd-200", "work-item:W-200" ]
    )
  end

  it "replays the exact persisted result without appending events" do
    original = operation.call(input)
    attempted_event_ids = event_store.attempted_event_ids.dup

    replay = operation.call(input)

    expect(replay).to be_success
    expect(replay.value!).to eq(original.value!)
    expect(event_store.attempted_event_ids).to eq(attempted_event_ids)
  end

  it "rejects reuse of the command ID with changed accepted input" do
    operation.call(input)

    result = operation.call(input.merge(goal: "A different goal"))

    expect(result).to be_failure
    expect(result.failure.code).to eq(:command_id_reused)
    expect(event_store.stream_events(streams.work_item("W-200")).length).to eq(1)
    expect(event_store.stream_events(streams.command("cmd-200")).length).to eq(1)
  end

  it "returns a zero-event duplicate denial without completing the losing command" do
    operation.call(input)

    result = operation.call(input.merge(command_id: "cmd-201"))

    expect(result).to be_failure
    expect(result.failure.code).to eq(:work_item_already_exists)
    expect(event_store.stream_events(streams.command("cmd-201"))).to be_empty
  end

  it "returns a zero-event denial when the ChangeSet is absent" do
    empty_store = FakeEventStore.new
    empty_operation = described_class.new(event_store: empty_store, clock:, id_generator:)

    result = empty_operation.call(input)

    expect(result).to be_failure
    expect(result.failure.code).to eq(:change_set_not_found)
    expect(empty_store.stream_events(streams.work_item("W-200"))).to be_empty
    expect(empty_store.stream_events(streams.command("cmd-200"))).to be_empty
  end

  it "rebuilds fresh events with stable IDs when the serializable block retries" do
    retrying_store = FakeEventStore.new(retry_once: true)
    seed_change_set(retrying_store)
    initial_attempts = retrying_store.attempted_event_ids.length
    retrying_operation = described_class.new(event_store: retrying_store, clock:, id_generator:)

    result = retrying_operation.call(input)

    expect(result).to be_success
    retried_ids = retrying_store.attempted_event_ids.drop(initial_attempts)
    expect(retried_ids.tally.values).to contain_exactly(2, 2, 2)
    expect(retrying_store.stream_events(streams.work_item("W-200")).length).to eq(1)
    expect(retrying_store.stream_events(streams.command("cmd-200")).length).to eq(1)
  end

  it "rolls back both domain facts when completion construction raises" do
    completion_builder = instance_double(Coordinator::CommandCompletionBuilder)
    allow(completion_builder).to receive(:work_item_create).and_raise("receipt invariant failed")
    failing_operation = described_class.new(
      event_store:,
      clock:,
      id_generator:,
      completion_builder:
    )

    expect { failing_operation.call(input) }.to raise_error("receipt invariant failed")
    expect(event_store.stream_events(streams.work_item("W-200"))).to be_empty
    expect(event_store.stream_events(streams.change_set("CS-100")).map(&:type)).to eq(
      [ "ChangeSetCreated", "ChangeSetAcceptanceCriteriaDefined" ]
    )
    expect(event_store.stream_events(streams.command("cmd-200"))).to be_empty
  end

  def seed_change_set(store)
    store.append(
      streams.change_set("CS-100"),
      [
        PgEventstore::Event.new(
          id: "018fd0f0-0000-7000-8000-000000000100",
          type: "ChangeSetCreated",
          data: {
            "change_set_id" => "CS-100",
            "goal" => "Coordinate billing changes",
            "created_at" => "2026-08-20T14:10:00.000000Z"
          },
          metadata: { "schema_version" => 1 }
        ),
        PgEventstore::Event.new(
          id: "018fd0f0-0000-7000-8000-000000000101",
          type: "ChangeSetAcceptanceCriteriaDefined",
          data: {
            "change_set_id" => "CS-100",
            "acceptance_criteria" => [ "Agents do not overlap" ],
            "defined_at" => "2026-08-20T14:10:00.000000Z"
          },
          metadata: { "schema_version" => 1 }
        )
      ]
    )
  end
end
