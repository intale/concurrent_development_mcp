# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteRecordReleaseSetVerification, :event_store do
  subject(:operation) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }

  it "records passing evidence bound to the exact successful integrations and preserves correlation" do
    prepared = ReleaseSetScenario.prepare(prefix: "verification-pass")
    integrations = ReleaseSetScenario.integrate_all(prepared, prefix: "verification-pass")
    input = verification_input(prepared, integrations, prefix: "verification-pass")

    first = operation.call(input).value!
    replay = operation.call(input)
    events = ReleaseSetScenario.release_lifecycle_events(input.fetch(:release_set_id))
    event = events.select { _1.type == "ReleaseSetVerificationRecorded" }.sole
    links = events.select { _1.type == "ReleaseSetIntegrationLinked" }
    payload = ReleaseSetScenario.load(event)

    expect(first).to be_a(Coordinator::Write::CommandResultV1)
    expect(replay.failure.code).to eq(:release_set_already_verified)
    expect(payload).to have_attributes(attempt_number: 1)
    expect(payload.evidence.outcome).to eq("passed")
    expect(links.map { ReleaseSetScenario.load(_1).integration_event }).to eq(
      integrations.map { _1.fetch(:completion).data.integration_event }
    )
    expect(event.metadata.fetch("verification_digest")).to eq(first.data.verification_digest)
    expect(event.data).not_to have_key("recorded_at")
    expect(event.correlation_id).to eq(prepared.fetch(:event).correlation_id)
  end

  it "denies stale or reordered integration references" do
    prepared = ReleaseSetScenario.prepare(prefix: "verification-stale")
    integrations = ReleaseSetScenario.integrate_all(prepared, prefix: "verification-stale")
    input = verification_input(prepared, integrations, prefix: "verification-stale")

    result = operation.call(input.merge(integration_events: input.fetch(:integration_events).reverse))

    expect(result.failure.code).to eq(:release_verification_integration_binding_stale)
    expect(ReleaseSetScenario.release_lifecycle_events(input.fetch(:release_set_id)).count { _1.type == "ReleaseSetVerificationRecorded" }).to eq(0)
  end

  it "records failed evidence and permits a later exact passing verification" do
    prepared = ReleaseSetScenario.prepare(prefix: "verification-retry")
    integrations = ReleaseSetScenario.integrate_all(prepared, prefix: "verification-retry")
    failed_input = verification_input(
      prepared,
      integrations,
      prefix: "verification-failed",
      outcome: "failed",
      findings: [
        {
          code: "cross_repo_failure",
          severity: "error",
          summary: "The composite suite failed.",
          repository_id: nil
        }
      ]
    )

    failed = operation.call(failed_input).value!
    passed = operation.call(verification_input(prepared, integrations, prefix: "verification-retry")).value!

    expect(failed.data).to have_attributes(outcome: "failed", attempt_number: 1)
    expect(passed.data).to have_attributes(outcome: "passed", attempt_number: 2)
  end

  it "closes composite verification after activation" do
    prepared = ReleaseSetScenario.prepare(prefix: "verification-after-activation")
    integrations = ReleaseSetScenario.integrate_all(
      prepared, prefix: "verification-after-activation"
    )
    verification = ReleaseSetScenario.record_verification(
      prepared, integrations:, prefix: "verification-after-activation"
    )
    ReleaseSetScenario.record_activation(
      prepared, verification:, prefix: "verification-after-activation"
    )
    input = verification_input(
      prepared, integrations, prefix: "verification-after-activation-retry"
    )

    result = operation.call(input)

    expect(result.failure.code).to eq(:release_set_already_activated)
  end

  it "closes composite verification after compensation is requested" do
    prepared = ReleaseSetScenario.prepare(prefix: "verification-after-compensation")
    integrations = ReleaseSetScenario.integrate_all(
      prepared, prefix: "verification-after-compensation"
    )
    failed = ReleaseSetScenario.record_verification(
      prepared,
      integrations:,
      prefix: "verification-after-compensation-failed",
      outcome: "failed",
      findings: [
        {
          code: "cross_repo_failure",
          severity: "error",
          summary: "The composite suite failed.",
          repository_id: nil
        }
      ]
    )
    Coordinator::Processes::ProcessManagers::ReleaseSetLifecycle.new(event_store:).call(
      failed.fetch(:event)
    )
    input = verification_input(
      prepared, integrations, prefix: "verification-after-compensation-retry"
    )

    result = operation.call(input)

    expect(result.failure.code).to eq(:release_set_compensation_requested)
  end

  def verification_input(prepared, integrations, prefix:, outcome: "passed", findings: [])
    {
      command_id: "cmd-release-verify-#{prefix}",
      actor: { kind: "agent", id: "release-verifier-1" },
      release_set_id: prepared.dig(:input, :release_set_id),
      integration_events: integrations.map { _1.fetch(:completion).data.integration_event.to_h },
      evidence: {
        producer: { name: "release-suite", version: "1.0.0" },
        run_id: "release-verification-#{prefix}",
        environment_digest: "sha256:#{'e' * 64}",
        result_digest: "sha256:#{outcome == 'passed' ? 'f' * 64 : 'd' * 64}",
        outcome:,
        findings:,
        produced_at: "2026-08-24T20:00:00.000000Z"
      }
    }
  end
end
