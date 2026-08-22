# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteAcquireWorkItem, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  subject(:operation) { described_class.new(event_store:) }

  let(:input) do
    {
      command_id: "cmd-300",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: "CS-100",
      work_item_id: "W-200",
      attempt_id: "A-300",
      base_snapshots: [
        {
          repository_id: "billing",
          commit_oid: "0123456789abcdef0123456789abcdef01234567"
        }
      ]
    }
  end

  it "atomically persists acquisition, authorization, start, and the durable receipt" do
    seed_ready_work_items("CS-100", [ [ "W-200", "billing" ] ])

    result = operation.call(input)

    expect(result).to be_success
    completion = result.value!
    expect(completion.data).to eq(
      Coordinator::Write::CommandReceiptData::Attempt.new(
        change_set_id: "CS-100",
        work_item_id: "W-200",
        attempt_id: "A-300"
      )
    )
    expect(work_item_events("W-200").map(&:type)).to eq(
      [ "WorkItemCreated", "WorkItemMadeReady", "WorkItemAcquired" ]
    )
    expect(attempt_events("A-300").map(&:type)).to eq([ "AttemptAuthorized", "AttemptStarted" ])
    expect(command_events("cmd-300").map(&:type)).to eq([ "CommandCompleted" ])

    authorized = attempt_events("A-300").first
    expect(authorized.data.fetch("base_snapshots")).to eq(
      [
        {
          "repository_id" => "billing",
          "object_format" => "sha1",
          "commit_oid" => "0123456789abcdef0123456789abcdef01234567"
        }
      ]
    )
    timestamps = [
      work_item_events("W-200").last.data.fetch("acquired_at"),
      authorized.data.fetch("authorized_at"),
      attempt_events("A-300").last.data.fetch("started_at"),
      completion.completed_at
    ]
    expect(timestamps.uniq.length).to eq(1)
    expect(completion.emitted_events.map { [ _1.stream_name, _1.stream_id, _1.stream_revision ] }).to eq(
      [ [ "WorkItem", "W-200", 2 ], [ "Attempt", "A-300", 0 ], [ "Attempt", "A-300", 1 ] ]
    )
  end

  it "writes the complete stable routing markers to every domain fact" do
    seed_ready_work_items("CS-100", [ [ "W-200", "billing" ] ])

    operation.call(input)

    expected_markers = [
      "attempt:A-300",
      "change-set:CS-100",
      "command:cmd-300",
      "repository:billing",
      "work-item:W-200"
    ]
    expect(work_item_events("W-200").last.markers).to eq(expected_markers)
    expect(attempt_events("A-300").map(&:markers)).to all(eq(expected_markers))
  end

  it "replays the exact persisted completion without another append" do
    seed_ready_work_items("CS-100", [ [ "W-200", "billing" ] ])
    original = operation.call(input)
    original_ids = acquisition_event_ids

    replay = operation.call(input)

    expect(replay).to be_success
    expect(replay.value!).to eq(original.value!)
    expect(acquisition_event_ids).to eq(original_ids)
  end

  it "rejects changed-input reuse of an accepted command ID" do
    seed_ready_work_items("CS-100", [ [ "W-200", "billing" ] ])
    operation.call(input)

    result = operation.call(input.merge(actor: { kind: "agent", id: "agent-b" }))

    expect(result).to be_failure
    expect(result.failure.code).to eq(:command_id_reused)
    expect(work_item_events("W-200").count { _1.type == "WorkItemAcquired" }).to eq(1)
    expect(command_events("cmd-300").length).to eq(1)
  end

  it "returns invalid_git_oid before opening a domain decision or receipt" do
    result = operation.call(
      input.merge(
        base_snapshots: [ { repository_id: "billing", commit_oid: "ABC" } ]
      )
    )

    expect(result).to be_failure
    expect(result.failure.code).to eq(:invalid_git_oid)
    expect(attempt_events("A-300")).to be_empty
    expect(command_events("cmd-300")).to be_empty
  end

  it "returns zero-event state and repository denials" do
    create_plan("CS-100", [ [ "W-200", "billing" ] ])
    inactive = operation.call(input.merge(command_id: "cmd-inactive", attempt_id: "A-inactive"))
    activate_change_set("CS-100")
    not_ready = operation.call(input.merge(command_id: "cmd-not-ready", attempt_id: "A-not-ready"))
    make_ready("CS-100")
    wrong_base = operation.call(
      input.merge(
        command_id: "cmd-wrong-base",
        attempt_id: "A-wrong-base",
        base_snapshots: [
          { repository_id: "ledger", commit_oid: "0123456789abcdef0123456789abcdef01234567" }
        ]
      )
    )

    expect(inactive.failure.code).to eq(:change_set_not_active)
    expect(not_ready.failure.code).to eq(:work_item_not_ready)
    expect(wrong_base.failure.code).to eq(:repository_base_mismatch)
    expect([ "A-inactive", "A-not-ready", "A-wrong-base" ].flat_map { attempt_events(_1) }).to be_empty
    expect([ "cmd-inactive", "cmd-not-ready", "cmd-wrong-base" ].flat_map { command_events(_1) }).to be_empty
  end

  it "does not reuse an Attempt identity already authorized for another WorkItem" do
    seed_ready_work_items(
      "CS-100",
      [
        [ "W-100", "billing" ],
        [ "W-200", "billing" ]
      ]
    )
    operation.call(input.merge(command_id: "cmd-first", work_item_id: "W-100"))

    result = operation.call(input.merge(command_id: "cmd-second"))

    expect(result).to be_failure
    expect(result.failure.code).to eq(:attempt_already_exists)
    expect(work_item_events("W-200").none? { _1.type == "WorkItemAcquired" }).to be(true)
    expect(command_events("cmd-second")).to be_empty
  end

  it "serializes simultaneous acquisitions so one WorkItem has exactly one active Attempt" do
    seed_ready_work_items("CS-100", [ [ "W-200", "billing" ] ])
    competing_inputs = [
      input.merge(command_id: "cmd-race-a", attempt_id: "A-race-a"),
      input.merge(
        command_id: "cmd-race-b",
        actor: { kind: "agent", id: "agent-b" },
        attempt_id: "A-race-b"
      )
    ]

    results = competing_inputs.map do |competing_input|
      Thread.new { described_class.new(event_store:).call(competing_input) }
    end.map(&:value)

    expect(results.count(&:success?)).to eq(1)
    expect(results.count(&:failure?)).to eq(1)
    expect(results.find(&:failure?).failure.code).to eq(:work_item_unavailable)
    expect(work_item_events("W-200").count { _1.type == "WorkItemAcquired" }).to eq(1)
    expect(competing_inputs.sum { attempt_events(_1.fetch(:attempt_id)).length }).to eq(2)
    expect(competing_inputs.sum { command_events(_1.fetch(:command_id)).length }).to eq(1)
  end

  def seed_ready_work_items(change_set_id, work_items)
    create_plan(change_set_id, work_items)
    activate_change_set(change_set_id)
    make_ready(change_set_id)
  end

  def create_plan(change_set_id, work_items)
    Coordinator::Write::Operations::ExecuteCreateChangeSet.new(event_store:).call(
      command_id: "seed-create-#{change_set_id}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id:,
      goal: "Coordinate #{change_set_id}",
      acceptance_criteria: [ "Agents do not overlap" ]
    ).value!

    work_items.each do |work_item_id, repository_id|
      Coordinator::Write::Operations::ExecuteCreateWorkItem.new(event_store:).call(
        command_id: "seed-create-#{work_item_id}",
        actor: { kind: "agent", id: "planner-1" },
        change_set_id:,
        work_item_id:,
        repository_id:,
        goal: "Implement #{work_item_id}",
        acceptance_criteria: [ "The work is verifiable" ]
      ).value!
    end
  end

  def activate_change_set(change_set_id)
    Coordinator::Write::Operations::ExecuteActivateChangeSet.new(event_store:).call(
      command_id: "seed-activate-#{change_set_id}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id:
    ).value!
  end

  def make_ready(change_set_id)
    activation = event_store.read(
      streams.change_set(change_set_id),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACQUISITION
    ).find { _1.type == "ChangeSetActivated" }
    Coordinator::Processes::ProcessManagers::ChangeSetReadiness.new(event_store:).call(activation)
  end

  def work_item_events(work_item_id)
    event_store.read(
      streams.work_item(work_item_id),
      Coordinator::Write::EventQueries::WORK_ITEM_FOR_ACQUISITION
    )
  end

  def attempt_events(attempt_id)
    event_store.read(
      streams.attempt(attempt_id),
      Coordinator::Write::EventQueries::ATTEMPT_FOR_ACQUISITION
    )
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_COMPLETION)
  end

  def acquisition_event_ids
    work_item_events("W-200").select { _1.type == "WorkItemAcquired" }.map(&:id) +
      attempt_events("A-300").map(&:id) +
      command_events("cmd-300").map(&:id)
  end
end
