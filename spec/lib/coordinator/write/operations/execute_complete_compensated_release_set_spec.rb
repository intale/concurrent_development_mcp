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

    expect(denied.failure.code).to eq(:release_compensation_evidence_mismatch)
    expect(completed).to be_success
    expect(replay.failure.code).to eq(:release_set_already_completed)
    expect(ReleaseSetScenario.load(completion_events.sole)).to have_attributes(
      outcome: "compensated",
      source_event: ReleaseSetScenario.reference(request.fetch(:event)),
      rule_version: "release-set-completion/v1"
    )
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
        result_digest: "sha256:#{'d' * 64}",
        occurred_at: "2026-08-24T21:30:00.000000Z"
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
    evidence = request.fetch(:payload).successful_integrations.map do |reference|
      integration = state.integrations.find { _1.event == reference }
      {
        repository_id: integration.payload.repository_id,
        integration_event: reference.to_h,
        action: "revert",
        external_reference: "reverts/#{prefix}",
        result_digest: "sha256:#{'e' * 64}",
        producer: { name: "release-reverter", version: "1.0.0" },
        run_id: "release-compensation-#{prefix}",
        compensated_at: "2026-08-24T22:00:00.000000Z"
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
