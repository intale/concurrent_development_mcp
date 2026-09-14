# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteCompleteWorkItem, :event_store do
  subject(:operation) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }

  it "atomically selects the final Candidate and completes its Attempt and WorkItem" do
    candidate = CandidateScenario.submit(prefix: "complete-success")
    CandidateScenario.release(candidate)
    input = CandidateScenario.completion_input(
      candidate,
      produced_outputs: [
        { kind: "contract", key: "payments-v2" },
        { kind: "artifact", key: "billing-gem" }
      ]
    )

    result = operation.call(input)

    expect(result).to be_success
    completion = result.value!
    expect(completion.data).to have_attributes(
      work_item_id: candidate.dig(:ids, :work_item_id),
      attempt_id: candidate.dig(:ids, :attempt_id),
      candidate_id: candidate.dig(:input, :candidate_id),
      produced_outputs: [
        have_attributes(kind: "artifact", key: "billing-gem"),
        have_attributes(kind: "contract", key: "payments-v2")
      ]
    )
    expect(completion.emitted_events.map(&:type)).to eq([
      "WorkItemCandidateSelected",
      "WorkItemOutputRecorded",
      "WorkItemOutputRecorded",
      "AttemptCompleted",
      "WorkItemCompleted"
    ])
    expect(completion.data.candidate_event.type).to eq("CandidateSubmitted")
    expect(completion.data.selected_event.type).to eq("WorkItemCandidateSelected")
    expect(completion.data.attempt_completed_event.type).to eq("AttemptCompleted")
    expect(completion.data.work_item_completed_event.type).to eq("WorkItemCompleted")
    expect(work_item_terminal_events(candidate).map(&:type)).to eq([
      "WorkItemCandidateSelected",
      "WorkItemCompleted"
    ])
    expect(attempt_terminal_events(candidate).map(&:type)).to eq([ "AttemptCompleted" ])
    expect(command_events(input.fetch(:command_id))).to be_empty
  end

  it "leaves replay ownership to the registered Command lifecycle" do
    candidate = CandidateScenario.submit(prefix: "complete-replay")
    CandidateScenario.release(candidate)
    input = CandidateScenario.completion_input(candidate)
    original = operation.call(input)
    event_ids = terminal_event_ids(candidate, input)

    replay = operation.call(input)
    changed = operation.call(
      input.merge(produced_outputs: [ { kind: "artifact", key: "changed" } ])
    )

    expect(replay.failure.code).to eq(:work_item_already_completed)
    expect(changed.failure.code).to eq(:work_item_already_completed)
    expect(terminal_event_ids(candidate, input)).to eq(event_ids)
  end

  it "uses Candidate and Attempt authority without consulting a stale read model" do
    candidate = CandidateScenario.submit(prefix: "complete-active-lease")
    input = CandidateScenario.completion_input(candidate)

    result = operation.call(input)

    expect(result).to be_success
    expect(work_item_terminal_events(candidate).map(&:type)).to eq(
      [ "WorkItemCandidateSelected", "WorkItemCompleted" ]
    )
    expect(attempt_terminal_events(candidate).map(&:type)).to eq([ "AttemptCompleted" ])
    expect(command_events(input.fetch(:command_id))).to be_empty
  end

  it "folds the bounded latest lifecycle after repeated interrupted Attempts" do
    candidate = recovered_candidate(prefix: "complete-recovered", interruption_count: 2)
    CandidateScenario.release(candidate)
    input = CandidateScenario.completion_input(candidate)

    result = operation.call(input)

    expect(result).to be_success
    lifecycle = work_item_lifecycle_events(candidate.dig(:ids, :work_item_id))
    expect(lifecycle.count { _1.type == "WorkItemAcquired" }).to eq(3)
    expect(lifecycle.count { _1.type == "WorkItemRequeued" }).to eq(2)
    expect(lifecycle.last.type).to eq("WorkItemCompleted")
  end

  it "serializes competing terminal commands so exactly one Candidate selection commits" do
    candidate = CandidateScenario.submit(prefix: "complete-race")
    CandidateScenario.release(candidate)
    inputs = %w[a b].map do |suffix|
      CandidateScenario.completion_input(candidate, command_id: "cmd-complete-race-#{suffix}")
    end

    results = inputs.map do |input|
      Thread.new { described_class.new(event_store:).call(input) }
    end.map(&:value)

    expect(results.count(&:success?)).to eq(1)
    expect(results.count(&:failure?)).to eq(1)
    expect(results.find(&:failure?).failure.code).to eq(:work_item_already_completed)
    expect(work_item_terminal_events(candidate).map(&:type)).to eq([
      "WorkItemCandidateSelected",
      "WorkItemCompleted"
    ])
    expect(attempt_terminal_events(candidate).map(&:type)).to eq([ "AttemptCompleted" ])
    expect(inputs.flat_map { command_events(_1.fetch(:command_id)) }).to be_empty
  end

  def work_item_terminal_events(candidate)
    event_store.read(
      streams.work_item(candidate.dig(:ids, :work_item_id)),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[WorkItemCandidateSelected WorkItemCompleted],
        maximum_count: 2,
        direction: :asc
      )
    )
  end

  def attempt_terminal_events(candidate)
    event_store.read(
      streams.attempt(candidate.dig(:ids, :attempt_id)),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "AttemptCompleted" ],
        maximum_count: 1,
        direction: :asc
      )
    )
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_HISTORY)
  end

  def recovered_candidate(prefix:, interruption_count:)
    path = "lib/candidate.rb"
    prepared = CandidateScenario.prepare(prefix:, path:)
    interruption_count.times do |index|
      abandon_attempt(prepared, prefix:, index:)
      prepared = reacquire(prepared, prefix:, path:, index:)
    end

    input = CandidateScenario.input(
      prefix:,
      ids: prepared.fetch(:ids),
      reservation: prepared.fetch(:reservation),
      path:,
      agent_id: "agent-a",
      candidate_id: "CAN-#{prefix}",
      command_id: "cmd-#{prefix}",
      head_commit_oid: "b" * 40
    )
    execute!(Coordinator::Write::Operations::ExecuteSubmitCandidate, input)
    prepared.merge(input:)
  end

  def abandon_attempt(candidate, prefix:, index:)
    ids = candidate.fetch(:ids)
    execute!(Coordinator::Write::Operations::ExecuteAbandonAttempt, {
      command_id: "cmd-#{prefix}-abandon-#{index}",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      reason: "The test agent was interrupted before producing a Candidate."
    })
  end

  def reacquire(candidate, prefix:, path:, index:)
    ids = candidate.fetch(:ids).merge(attempt_id: "A-#{prefix}-recovery-#{index}")
    execute!(Coordinator::Write::Operations::ExecuteAcquireWorkItem, {
      command_id: "cmd-#{prefix}-acquire-#{index}",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      base_snapshots: [
        { repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID, commit_oid: "a" * 40 }
      ]
    })
    resource_id = ResourceScenario.resolve(
      event_store:,
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      kind: "file",
      path:
    )
    reservation = execute!(Coordinator::Write::Operations::ExecuteReserveWriteSet, {
      command_id: "cmd-#{prefix}-reserve-#{index}",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      base_commit_oid: "a" * 40,
      resources: [ { resource_id:, base_blob_oid: "c" * 40 } ],
      ttl_seconds: 900
    }).data

    candidate.merge(ids:, reservation:)
  end

  def execute!(operation_class, input)
    operation_class.new(event_store:).call(input).value!
  end

  def work_item_lifecycle_events(work_item_id)
    event_store.read(
      streams.work_item(work_item_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[
          WorkItemCreated
          WorkItemMadeReady
          WorkItemAcquired
          WorkItemRequeued
          WorkItemCandidateSelected
          WorkItemCompleted
        ],
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def terminal_event_ids(candidate, input)
    [
      *work_item_terminal_events(candidate),
      *attempt_terminal_events(candidate),
      *command_events(input.fetch(:command_id))
    ].map(&:id).sort
  end
end
