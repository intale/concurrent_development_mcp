# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteCompleteCompensatedReleaseSet, :event_store do
  subject(:operation) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }

  it "requires exact member evidence and then completes compensation once" do
    prepared, request = compensation_requested("compensation-complete")
    correct = compensation_input(prepared, request, "compensation-complete")
    stale = correct.merge(
      command_id: "cmd-release-compensation-stale",
      evidence: correct.fetch(:evidence).map { _1.merge(repository_id: RepositoryScenario.repository_id("wrong-repository")) }
    )

    denied = operation.call(stale)
    completed = operation.call(correct)
    replay = operation.call(correct)
    completion_events = ReleaseSetScenario.release_lifecycle_events(
      prepared.dig(:input, :release_set_id)
    ).select { _1.type == "ReleaseSetCompleted" }
    outcome_events = ReleaseSetScenario.release_lifecycle_events(
      prepared.dig(:input, :release_set_id)
    ).select { _1.type == "ReleaseSetOutcomeRecorded" }
    compensation_events = ReleaseSetScenario.release_lifecycle_events(
      prepared.dig(:input, :release_set_id)
    ).select { _1.type == "RepositoryCompensationRecorded" }

    expect(denied.failure.code).to eq(:release_compensation_evidence_mismatch)
    expect(completed).to be_success
    expect(replay.failure.code).to eq(:release_set_already_completed)
    compensation = compensation_events.sole
    compensation_payload = ReleaseSetScenario.load(compensation)
    requested_evidence = correct.fetch(:evidence).sole
    expect(compensation_payload).to have_attributes(
      release_set_id: prepared.dig(:input, :release_set_id),
      repository_id: requested_evidence.fetch(:repository_id),
      integration_event: Coordinator::Write::EventReference.new(requested_evidence.fetch(:integration_event)),
      action: requested_evidence.fetch(:action),
      external_reference: requested_evidence.fetch(:external_reference)
    )
    expect(compensation.data.keys).to contain_exactly(
      "release_set_id", "repository_id", "integration_event", "action", "external_reference"
    )
    expect(compensation.metadata).to include(
      "result_digest" => requested_evidence.fetch(:result_digest),
      "producer" => requested_evidence.fetch(:producer).transform_keys(&:to_s),
      "run_id" => requested_evidence.fetch(:run_id)
    )
    outcome = outcome_events.sole
    expect(ReleaseSetScenario.load(outcome)).to have_attributes(outcome: "compensated")
    expect(ReleaseSetScenario.load(completion_events.sole).to_h).to eq(
      release_set_id: prepared.dig(:input, :release_set_id)
    )
    expect(outcome.metadata).to include("rule_version" => "release-set-completion/v1")
    expect(outcome.causation_id).to eq(compensation.id)
    expect(completion_events.sole.causation_id).to eq(outcome.id)
    history = Coordinator::Write::ReleaseSets::HistoryLoader.new(event_store:).call(
      prepared.dig(:input, :release_set_id)
    )
    expect(history.completion.compensation_evidence.map(&:to_h)).to eq(correct.fetch(:evidence))
  end

  private

  def compensation_requested(prefix)
    prepared = ReleaseSetScenario.prepare(prefix:)
    observation = ReleaseSetScenario.observe_member(prepared, index: 0, prefix:)
    ReleaseSetScenario.record_integration(prepared, index: 0, prefix:, observation:)
    failure = ReleaseSetScenario.record_integration(
      prepared,
      index: 1,
      prefix:,
      failure: {
        code: "deployment-failed",
        summary: "Ledger integration failed",
        producer: { name: "release-adapter", version: "1.0.0" },
        run_id: "release-failure-#{prefix}",
        result_digest: "sha256:#{'d' * 64}"
      }
    )
    Coordinator::Processes::ProcessManagers::ReleaseSetLifecycle.new(event_store:).call(failure.fetch(:event))
    request_event = ReleaseSetScenario.release_lifecycle_events(
      prepared.dig(:input, :release_set_id)
    ).find { _1.type == "ReleaseSetCompensationRequested" }
    [ prepared, { event: request_event, payload: ReleaseSetScenario.load(request_event) } ]
  end

  def compensation_input(prepared, request, prefix)
    state = Coordinator::Write::ReleaseSets::HistoryLoader.new(event_store:).call(
      prepared.dig(:input, :release_set_id)
    )
    evidence = state.compensation_request.successful_integrations.map do |reference|
      integration = state.integrations.find { _1.event == reference }
      {
        repository_id: integration.payload.repository_id,
        integration_event: reference.to_h,
        action: "revert",
        external_reference: "reverts/#{prefix}",
        result_digest: "sha256:#{'e' * 64}",
        producer: { name: "release-reverter", version: "1.0.0" },
        run_id: "release-compensation-#{prefix}"
      }
    end
    {
      command_id: "cmd-release-compensation-complete-#{prefix}",
      actor: { kind: "agent", id: "release-operator-1" },
      release_set_id: prepared.dig(:input, :release_set_id),
      compensation_request_event: ReleaseSetScenario.reference(request.fetch(:event)).to_h,
      evidence:
    }
  end
end
