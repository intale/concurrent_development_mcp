# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteAbandonAttempt, :event_store do
  subject(:operation) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }

  it "returns one successful command result while preserving an intermediate Candidate" do
    candidate = CandidateScenario.submit(
      prefix: "abandon-intermediate",
      checkpoint_kind: "intermediate"
    )

    result = operation.call(abandon_input(candidate))

    expect(result).to be_success
    expect(result.value!).to be_a(Coordinator::Write::CommandResultV1)
    expect(result.value!.emitted_events.map(&:type)).to eq([
      "ResourceWorkIntentionWithdrawn",
      "AttemptAbandoned",
      "WorkItemRequeued"
    ])
    expect(candidate_events(candidate).map(&:type)).to include("CandidateSubmitted")
  end

  it "rejects abandonment after a final Candidate without terminal domain facts" do
    candidate = CandidateScenario.submit(prefix: "abandon-final")

    result = operation.call(abandon_input(candidate))

    expect(result.failure).to have_attributes(
      code: :attempt_not_active,
      message: "Attempt has a final Candidate and must be completed instead of abandoned"
    )
    expect(attempt_terminal_events(candidate)).to be_empty
    expect(work_item_requeue_events(candidate)).to be_empty
  end

  def abandon_input(candidate)
    input = candidate.fetch(:input)
    {
      command_id: "cmd-abandon-#{input.fetch(:candidate_id)}",
      actor: input.fetch(:actor),
      change_set_id: input.fetch(:change_set_id),
      work_item_id: input.fetch(:work_item_id),
      attempt_id: input.fetch(:attempt_id),
      reason: "The test agent was interrupted after checkpointing its work."
    }
  end

  def candidate_events(candidate)
    event_store.read(
      streams.candidate(candidate.dig(:input, :candidate_id)),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "CandidateSubmitted" ],
        maximum_count: 1,
        direction: :asc
      )
    )
  end

  def attempt_terminal_events(candidate)
    event_store.read(
      streams.attempt(candidate.dig(:ids, :attempt_id)),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "AttemptAbandoned" ],
        maximum_count: 1,
        direction: :asc
      )
    )
  end

  def work_item_requeue_events(candidate)
    event_store.read(
      streams.work_item(candidate.dig(:ids, :work_item_id)),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "WorkItemRequeued" ],
        maximum_count: 1,
        direction: :asc
      )
    )
  end
end
