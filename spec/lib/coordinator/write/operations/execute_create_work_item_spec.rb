# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteCreateWorkItem, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  subject(:operation) { described_class.new(event_store:) }

  let(:repository_id) { "018f22a2-7b9c-7def-8abc-1234567890ab" }
  let(:repository_scope) { "project:billing" }
  let(:input) do
    {
      command_id: "cmd-200",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-100",
      work_item_id: "W-200",
      repository_id:,
      goal: "Implement capture validation",
      acceptance_criteria: [ "Reject duplicate ownership" ]
    }
  end

  before do
    register_repository(repository_id, scope: repository_scope)
    create_change_set("CS-100")
  end

  it "persists cohesive WorkItem facts and returns a transient typed result" do
    result = operation.call(input)

    expect(result).to be_success
    completion = result.value!
    expect(completion.data).to eq(
      Coordinator::Write::CommandReceiptData::WorkItem.new(
        change_set_id: "CS-100",
        work_item_id: "W-200"
      )
    )
    expect(work_item_events("W-200").map(&:type)).to eq(
      %w[
        WorkItemCreated
        WorkItemAddedToChangeSet
        WorkItemAssignedToRepository
        WorkItemGoalDefined
        WorkItemAcceptanceCriteriaDefined
        WorkItemCompetitiveModeSelected
      ]
    )
    expect(change_set_events("CS-100").map(&:type)).to eq(
      [ "ChangeSetCreated", "ChangeSetAcceptanceCriteriaDefined" ]
    )
    expect(command_events("cmd-200")).to be_empty
    expect(completion.emitted_events.map { [ _1.stream_name, _1.stream_revision ] }).to eq(
      (0..5).map { [ "WorkItem", _1 ] }
    )
  end

  it "writes the routing markers on real persisted events" do
    operation.call(input)

    facts = work_item_events("W-200")
    repository_markers = Coordinator::Write::RepositoryMarkerBuilder.new.call(
      Coordinator::Write::RepositoryRegistrationLoader.new(event_store:).call(repository_id)
    )
    common = [ "change-set:CS-100", "command:cmd-200", "work-item:W-200" ] + repository_markers
    expect(facts).to all(have_attributes(markers: contain_exactly(*common)))
  end

  it "leaves replay ownership to the registered Command lifecycle" do
    expect(operation.call(input)).to be_success
    original_ids = persisted_ids

    replay = operation.call(input)

    expect(replay.failure.code).to eq(:work_item_already_exists)
    expect(persisted_ids).to eq(original_ids)
  end

  it "enforces the WorkItem identity independently of public request identity" do
    operation.call(input)

    result = operation.call(input.merge(goal: "A different goal"))

    expect(result).to be_failure
    expect(result.failure.code).to eq(:work_item_already_exists)
    expect(work_item_events("W-200").length).to eq(6)
    expect(command_events("cmd-200")).to be_empty
  end

  it "returns a zero-event duplicate denial without completing the losing command" do
    operation.call(input)

    result = operation.call(input.merge(command_id: "cmd-201"))

    expect(result).to be_failure
    expect(result.failure.code).to eq(:work_item_already_exists)
    expect(command_events("cmd-201")).to be_empty
  end

  it "returns a zero-event denial when the ChangeSet is absent" do
    missing_input = input.merge(
      command_id: "cmd-missing",
      change_set_id: "CS-missing",
      work_item_id: "W-missing"
    )

    result = operation.call(missing_input)

    expect(result).to be_failure
    expect(result.failure.code).to eq(:change_set_not_found)
    expect(work_item_events("W-missing")).to be_empty
    expect(command_events("cmd-missing")).to be_empty
  end

  it "rejects a well-formed but unregistered repository without writing coordination facts" do
    unregistered_id = "018f22a2-7b9c-7def-9abc-1234567890ab"
    missing_input = input.merge(
      command_id: "cmd-unregistered",
      work_item_id: "W-unregistered",
      repository_id: unregistered_id
    )

    result = operation.call(missing_input)

    expect(result).to be_failure
    expect(result.failure).to have_attributes(
      code: :repository_not_registered,
      details: { repository_id: unregistered_id }
    )
    expect(work_item_events("W-unregistered")).to be_empty
    expect(command_events("cmd-unregistered")).to be_empty
  end

  it "serializes concurrent real commands so exactly one creates the WorkItem" do
    competing_inputs = [
      input.merge(command_id: "cmd-concurrent-1"),
      input.merge(command_id: "cmd-concurrent-2")
    ]

    results = competing_inputs.map do |competing_input|
      Thread.new { described_class.new(event_store:).call(competing_input) }
    end.map(&:value)

    expect(results.count(&:success?)).to eq(1)
    expect(results.count(&:failure?)).to eq(1)
    expect(results.find(&:failure?).failure.code).to eq(:work_item_already_exists)
    expect(work_item_events("W-200").length).to eq(6)
    expect(work_item_events("W-200").count { _1.type == "WorkItemAddedToChangeSet" }).to eq(1)
    expect(competing_inputs.flat_map { command_events(_1.fetch(:command_id)) }).to be_empty
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

  def register_repository(repository_id, scope:)
    Coordinator::Write::Operations::ExecuteRegisterRepository.new(event_store:).call(
      command_id: "seed-register-#{repository_id}",
      actor: { kind: "agent", id: "planner-1" },
      repository_id:,
      scope:,
      repository_key: "billing",
      display_name: "Billing",
      paths: [ "/workspace/billing" ],
      remotes: [ "https://example.test/billing.git" ]
    ).value!
  end

  def change_set_events(change_set_id)
    event_store.read(
      streams.change_set(change_set_id),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACTIVATION
    )
  end

  def work_item_events(work_item_id)
    event_store.read(
      streams.work_item(work_item_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[
          WorkItemCreated
          WorkItemAddedToChangeSet
          WorkItemAssignedToRepository
          WorkItemGoalDefined
          WorkItemAcceptanceCriteriaDefined
          WorkItemCompetitiveModeSelected
        ],
        maximum_count: 6,
        direction: :asc
      )
    )
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_HISTORY)
  end

  def persisted_ids
    work_item_events("W-200").map(&:id) + command_events("cmd-200").map(&:id)
  end
end
