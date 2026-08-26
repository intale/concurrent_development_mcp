# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteDeclareWorkItemDependency, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  subject(:operation) { described_class.new(event_store:) }

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
    create_change_set
    create_work_item("W-100", "billing")
    create_work_item("W-200", "ledger")
  end

  it "persists the dependency fact and durable completion through the real store" do
    result = operation.call(input)

    expect(result).to be_success
    completion = result.value!
    expect(completion.data).to eq(
      Coordinator::Write::CommandReceiptData::Dependency.new(
        change_set_id: "CS-100",
        dependency_id: "DEP-1"
      )
    )
    expect(change_set_events.map(&:type)).to eq(
      [
        "ChangeSetCreated",
        "ChangeSetAcceptanceCriteriaDefined",
        "WorkItemAddedToChangeSet",
        "WorkItemAddedToChangeSet",
        "WorkItemDependencyDeclared"
      ]
    )
    expect(command_events("cmd-230").map(&:type)).to eq([ "CommandCompleted" ])
    expect(completion.emitted_events.map { [ _1.stream_name, _1.stream_revision ] }).to eq(
      [ [ "ChangeSet", 4 ] ]
    )
  end

  it "writes stable routing markers on the real graph edge" do
    operation.call(input)

    event = dependency_events.sole
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

  it "replays the exact persisted completion without another real append" do
    original = operation.call(input)
    original_ids = persisted_ids

    replay = operation.call(input)

    expect(replay).to be_success
    expect(replay.value!).to eq(original.value!)
    expect(persisted_ids).to eq(original_ids)
  end

  it "rejects changed-input reuse of a completed command ID" do
    operation.call(input)

    result = operation.call(input.merge(dependency_kind: "requires_completion"))

    expect(result).to be_failure
    expect(result.failure.code).to eq(:command_id_reused)
    expect(command_events("cmd-230").length).to eq(1)
  end

  it "returns a zero-event cycle denial without completing the command" do
    declare_reverse_dependency

    result = operation.call(input)

    expect(result).to be_failure
    expect(result.failure.code).to eq(:dependency_cycle)
    expect(dependency_events.length).to eq(1)
    expect(command_events("cmd-230")).to be_empty
  end

  it "serializes concurrent real commands so exactly one declares the dependency" do
    competing_inputs = [
      input.merge(command_id: "cmd-concurrent-1"),
      input.merge(command_id: "cmd-concurrent-2")
    ]

    results = competing_inputs.map do |competing_input|
      Thread.new { described_class.new(event_store:).call(competing_input) }
    end.map(&:value)

    expect(results.count(&:success?)).to eq(1)
    expect(results.count(&:failure?)).to eq(1)
    expect(results.find(&:failure?).failure.code).to eq(:dependency_id_reused)
    expect(dependency_events.length).to eq(1)
    expect(competing_inputs.count { command_events(_1.fetch(:command_id)).one? }).to eq(1)
  end

  def create_change_set
    Coordinator::Write::Operations::ExecuteCreateChangeSet.new(event_store:).call(
      command_id: "seed-create-CS-100",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-100",
      goal: "Coordinate billing changes",
      acceptance_criteria: [ "Agents do not overlap" ]
    ).value!
  end

  def create_work_item(work_item_id, repository_id)
    repository_key = repository_id
    repository_id = RepositoryScenario.repository_id(repository_key)
    RepositoryScenario.register(event_store:, key: repository_key, repository_id:)
    Coordinator::Write::Operations::ExecuteCreateWorkItem.new(event_store:).call(
      command_id: "seed-create-#{work_item_id}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-100",
      work_item_id:,
      repository_id:,
      goal: "Implement #{work_item_id}",
      acceptance_criteria: [ "The work is verifiable" ]
    ).value!
  end

  def declare_reverse_dependency
    described_class.new(event_store:).call(
      input.merge(
        command_id: "seed-reverse-dependency",
        dependency_id: "DEP-reverse",
        producer_work_item_id: "W-200",
        consumer_work_item_id: "W-100"
      )
    ).value!
  end

  def change_set_events
    event_store.read(
      streams.change_set("CS-100"),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACTIVATION
    )
  end

  def dependency_events
    change_set_events.select { _1.type == "WorkItemDependencyDeclared" }
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_COMPLETION)
  end

  def persisted_ids
    dependency_events.map(&:id) + command_events("cmd-230").map(&:id)
  end
end
