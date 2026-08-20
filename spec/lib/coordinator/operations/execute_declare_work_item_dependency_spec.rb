# frozen_string_literal: true

RSpec.describe Coordinator::Operations::ExecuteDeclareWorkItemDependency do
  let(:event_store) { FakeEventStore.new }
  let(:clock) { TestSupport::FixedClock.new("2026-08-20T14:14:00.000000Z") }
  let(:id_generator) { TestSupport::DeterministicIdGenerator.new }
  let(:streams) { Coordinator::StreamFactory.new }
  subject(:operation) do
    described_class.new(event_store:, clock:, id_generator:)
  end

  let(:input) do
    {
      command_id: "cmd-230",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-100",
      dependency_id: "DEP-1",
      producer_work_item_id: "W-100",
      consumer_work_item_id: "W-200",
      dependency_kind: "requires_candidate",
      required_output: nil
    }
  end

  before do
    seed_change_set(event_store)
  end

  it "atomically persists the dependency fact and durable completion" do
    result = operation.call(input)

    expect(result).to be_success
    completion = result.value!
    expect(completion.data).to eq(
      Coordinator::CommandReceiptData::Dependency.new(
        change_set_id: "CS-100",
        dependency_id: "DEP-1"
      )
    )
    expect(event_store.stream_events(streams.change_set("CS-100")).map(&:type)).to eq(
      [
        "ChangeSetCreated",
        "ChangeSetAcceptanceCriteriaDefined",
        "WorkItemAddedToChangeSet",
        "WorkItemAddedToChangeSet",
        "WorkItemDependencyDeclared"
      ]
    )
    expect(event_store.stream_events(streams.command("cmd-230")).map(&:type)).to eq([ "CommandCompleted" ])
    expect(completion.projection_barriers.coord_context_v1.map(&:to_h)).to contain_exactly(
      hash_including(stream_name: "ChangeSet", stream_revision: 4)
    )
    expect(event_store.multiple_calls).to eq(1)
  end

  it "writes stable routing markers for the graph edge" do
    operation.call(input)

    event = event_store.stream_events(streams.change_set("CS-100")).last
    expect(event.markers).to eq(
      [
        "change-set:CS-100",
        "command:cmd-230",
        "dependency:DEP-1",
        "work-item:W-100",
        "work-item:W-200"
      ]
    )
  end

  it "replays the exact completion without appending" do
    original = operation.call(input)
    attempted_event_ids = event_store.attempted_event_ids.dup

    replay = operation.call(input)

    expect(replay).to be_success
    expect(replay.value!).to eq(original.value!)
    expect(event_store.attempted_event_ids).to eq(attempted_event_ids)
  end

  it "rejects changed-input reuse of a completed command ID" do
    operation.call(input)

    result = operation.call(input.merge(dependency_kind: "requires_completion"))

    expect(result).to be_failure
    expect(result.failure.code).to eq(:command_id_reused)
    expect(event_store.stream_events(streams.command("cmd-230")).length).to eq(1)
  end

  it "returns a zero-event cycle denial without completing the command" do
    seed_reverse_dependency(event_store)

    result = operation.call(input)

    expect(result).to be_failure
    expect(result.failure.code).to eq(:dependency_cycle)
    expect(event_store.stream_events(streams.change_set("CS-100")).last.type).to eq(
      "WorkItemDependencyDeclared"
    )
    expect(event_store.stream_events(streams.command("cmd-230"))).to be_empty
  end

  it "rebuilds fresh events with stable logical IDs on transaction retry" do
    retrying_store = FakeEventStore.new(retry_once: true)
    seed_change_set(retrying_store)
    initial_attempts = retrying_store.attempted_event_ids.length
    retrying_operation = described_class.new(event_store: retrying_store, clock:, id_generator:)

    result = retrying_operation.call(input)

    expect(result).to be_success
    retried_ids = retrying_store.attempted_event_ids.drop(initial_attempts)
    expect(retried_ids.tally.values).to contain_exactly(2, 2)
    expect(retrying_store.stream_events(streams.command("cmd-230")).length).to eq(1)
  end

  it "rolls back the dependency fact when completion construction raises" do
    completion_builder = instance_double(Coordinator::CommandCompletionBuilder)
    allow(completion_builder).to receive(:work_item_dependency_declare).and_raise("receipt invariant failed")
    failing_operation = described_class.new(
      event_store:,
      clock:,
      id_generator:,
      completion_builder:
    )

    expect { failing_operation.call(input) }.to raise_error("receipt invariant failed")
    expect(event_store.stream_events(streams.change_set("CS-100")).map(&:type)).to eq(
      [
        "ChangeSetCreated",
        "ChangeSetAcceptanceCriteriaDefined",
        "WorkItemAddedToChangeSet",
        "WorkItemAddedToChangeSet"
      ]
    )
    expect(event_store.stream_events(streams.command("cmd-230"))).to be_empty
  end

  def seed_change_set(store)
    store.append(
      streams.change_set("CS-100"),
      [
        persisted_event(
          id_suffix: "100",
          type: "ChangeSetCreated",
          data: {
            "change_set_id" => "CS-100",
            "goal" => "Coordinate billing changes",
            "created_at" => "2026-08-20T14:10:00.000000Z"
          }
        ),
        persisted_event(
          id_suffix: "101",
          type: "ChangeSetAcceptanceCriteriaDefined",
          data: {
            "change_set_id" => "CS-100",
            "acceptance_criteria" => [ "Agents do not overlap" ],
            "defined_at" => "2026-08-20T14:10:00.000000Z"
          }
        ),
        persisted_event(
          id_suffix: "102",
          type: "WorkItemAddedToChangeSet",
          data: {
            "change_set_id" => "CS-100",
            "work_item_id" => "W-100",
            "added_at" => "2026-08-20T14:12:00.000000Z"
          }
        ),
        persisted_event(
          id_suffix: "103",
          type: "WorkItemAddedToChangeSet",
          data: {
            "change_set_id" => "CS-100",
            "work_item_id" => "W-200",
            "added_at" => "2026-08-20T14:13:00.000000Z"
          }
        )
      ]
    )
  end

  def seed_reverse_dependency(store)
    store.append(
      streams.change_set("CS-100"),
      persisted_event(
        id_suffix: "104",
        type: "WorkItemDependencyDeclared",
        data: {
          "change_set_id" => "CS-100",
          "dependency_id" => "DEP-existing",
          "producer_work_item_id" => "W-200",
          "consumer_work_item_id" => "W-100",
          "dependency_kind" => "requires_completion",
          "required_output" => nil,
          "declared_at" => "2026-08-20T14:13:30.000000Z"
        }
      )
    )
  end

  def persisted_event(id_suffix:, type:, data:)
    PgEventstore::Event.new(
      id: "018fd0f0-0000-7000-8000-000000000#{id_suffix}",
      type:,
      data:,
      metadata: { "schema_version" => 1 }
    )
  end
end
