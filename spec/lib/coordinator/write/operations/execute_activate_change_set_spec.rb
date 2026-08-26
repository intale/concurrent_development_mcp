# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteActivateChangeSet, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  subject(:operation) { described_class.new(event_store:) }

  let(:input) do
    {
      command_id: "cmd-250",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-100"
    }
  end

  before do
    seed_activatable_change_set
  end

  it "persists activation and its durable typed completion through the real store" do
    result = operation.call(input)

    expect(result).to be_success
    completion = result.value!
    activation = activation_events("CS-100").sole
    expect(activation.data).to include(
      "change_set_id" => "CS-100",
      "work_item_count" => 2,
      "dependency_count" => 1
    )
    expect(activation.data.fetch("activated_at")).to match(Coordinator::Shared::Types::TIMESTAMP_PATTERN)
    expect(completion.data).to eq(
      Coordinator::Write::CommandReceiptData::ChangeSet.new(change_set_id: "CS-100")
    )
    expect(completion.emitted_events.map { [ _1.stream_name, _1.stream_revision ] }).to eq(
      [ [ "ChangeSet", 5 ] ]
    )
    expect(command_events("cmd-250").map(&:type)).to eq([ "CommandCompleted" ])
  end

  it "returns a typed coord_context next action after the activation receipt" do
    completion = operation.call(input).value!

    expect(completion.next_actions).to contain_exactly(
      Coordinator::Write::NextAction.new(
        tool: "coord_context",
        arguments: Coordinator::Write::NextAction::ChangeSetArguments.new(change_set_id: "CS-100")
      )
    )
  end

  it "writes only stable ChangeSet and command routing markers" do
    operation.call(input)

    expect(activation_events("CS-100").sole.markers).to eq(
      [ "change-set:CS-100", "command:cmd-250" ]
    )
  end

  it "replays the exact typed completion without another real append" do
    original = operation.call(input)
    original_ids = persisted_ids

    replay = operation.call(input)

    expect(replay).to be_success
    expect(replay.value!).to eq(original.value!)
    expect(replay.value!.data).to be_a(Coordinator::Write::CommandReceiptData::ChangeSet)
    expect(persisted_ids).to eq(original_ids)
  end

  it "rejects changed-input reuse of the completed command ID" do
    operation.call(input)

    result = operation.call(input.merge(actor: { kind: "agent", id: "planner-2" }))

    expect(result).to be_failure
    expect(result.failure.code).to eq(:command_id_reused)
    expect(command_events("cmd-250").length).to eq(1)
  end

  it "returns a zero-event invalid-plan denial without a receipt" do
    create_change_set("CS-empty")
    invalid_input = input.merge(command_id: "cmd-empty", change_set_id: "CS-empty")

    result = operation.call(invalid_input)

    expect(result).to be_failure
    expect(result.failure.code).to eq(:change_set_has_no_work_items)
    expect(command_events("cmd-empty")).to be_empty
    expect(activation_events("CS-empty")).to be_empty
  end

  it "serializes concurrent real commands so exactly one activates the ChangeSet" do
    competing_inputs = [
      input.merge(command_id: "cmd-concurrent-1"),
      input.merge(command_id: "cmd-concurrent-2")
    ]

    results = competing_inputs.map do |competing_input|
      Thread.new { described_class.new(event_store:).call(competing_input) }
    end.map(&:value)

    expect(results.count(&:success?)).to eq(1)
    expect(results.count(&:failure?)).to eq(1)
    expect(results.find(&:failure?).failure.code).to eq(:change_set_already_active)
    expect(activation_events("CS-100").length).to eq(1)
    expect(competing_inputs.count { command_events(_1.fetch(:command_id)).one? }).to eq(1)
  end

  def seed_activatable_change_set
    create_change_set("CS-100")
    create_work_item("W-100", "billing")
    create_work_item("W-200", "ledger")
    create_dependency
  end

  def create_change_set(change_set_id)
    Coordinator::Write::Operations::ExecuteCreateChangeSet.new(event_store:).call(
      command_id: "seed-create-#{change_set_id}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id:,
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

  def create_dependency
    Coordinator::Write::Operations::ExecuteDeclareWorkItemDependency.new(event_store:).call(
      command_id: "seed-create-DEP-1",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-100",
      dependency_id: "DEP-1",
      producer_work_item_id: "W-100",
      consumer_work_item_id: "W-200",
      dependency_kind: "requires_candidate",
      required_output: nil
    ).value!
  end

  def change_set_events(change_set_id)
    event_store.read(
      streams.change_set(change_set_id),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACTIVATION
    )
  end

  def activation_events(change_set_id)
    change_set_events(change_set_id).select { _1.type == "ChangeSetActivated" }
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_COMPLETION)
  end

  def persisted_ids
    activation_events("CS-100").map(&:id) + command_events("cmd-250").map(&:id)
  end
end
