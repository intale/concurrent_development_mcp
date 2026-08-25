# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteCompleteWorkItem, :event_store do
  subject(:operation) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }

  it "atomically selects the final Candidate and completes its Attempt, WorkItem, and command" do
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
    expect(command_events(input.fetch(:command_id)).map(&:type)).to eq([ "CommandCompleted" ])
  end

  it "replays the same canonical input and rejects changed command reuse" do
    candidate = CandidateScenario.submit(prefix: "complete-replay")
    CandidateScenario.release(candidate)
    input = CandidateScenario.completion_input(candidate)
    original = operation.call(input)
    event_ids = terminal_event_ids(candidate, input)

    replay = operation.call(input)
    changed = operation.call(
      input.merge(produced_outputs: [ { kind: "artifact", key: "changed" } ])
    )

    expect(replay).to be_success
    expect(replay.value!).to eq(original.value!)
    expect(changed.failure.code).to eq(:command_id_reused)
    expect(terminal_event_ids(candidate, input)).to eq(event_ids)
  end

  it "does not append terminal facts while the authoritative write set remains active" do
    candidate = CandidateScenario.submit(prefix: "complete-active-lease")
    input = CandidateScenario.completion_input(candidate)

    result = operation.call(input)

    expect(result.failure.code).to eq(:write_set_still_active)
    expect(work_item_terminal_events(candidate)).to be_empty
    expect(attempt_terminal_events(candidate)).to be_empty
    expect(command_events(input.fetch(:command_id))).to be_empty
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
    expect(inputs.sum { command_events(_1.fetch(:command_id)).length }).to eq(1)
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
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_COMPLETION)
  end

  def terminal_event_ids(candidate, input)
    [
      *work_item_terminal_events(candidate),
      *attempt_terminal_events(candidate),
      *command_events(input.fetch(:command_id))
    ].map(&:id).sort
  end
end
