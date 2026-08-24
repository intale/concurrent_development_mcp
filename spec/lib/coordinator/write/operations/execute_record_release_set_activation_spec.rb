# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteRecordReleaseSetActivation, :event_store do
  subject(:operation) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }

  it "records an exact attributed activation and replays without duplicate facts" do
    prepared = ReleaseSetScenario.prepare(prefix: "activation-success")
    integrations = ReleaseSetScenario.integrate_all(prepared, prefix: "activation-success")
    verification = ReleaseSetScenario.record_verification(
      prepared, integrations:, prefix: "activation-success"
    )
    input = ReleaseSetScenario.record_activation(
      prepared, verification:, prefix: "activation-success"
    ).fetch(:input)

    replay = operation.call(input)
    events = ReleaseSetScenario.release_lifecycle_events(input.fetch(:release_set_id))
    activation = events.select { _1.type == "ReleaseSetActivated" }.sole
    payload = ReleaseSetScenario.load(activation)

    expect(replay).to be_success
    expect(payload).to have_attributes(
      verification_event: verification.fetch(:completion).data.verification_event,
      verification_digest: verification.fetch(:payload).verification_digest,
      evidence_status: "attributed_unverified",
      policy_version: "release-set-activation/v1"
    )
    expect(activation.correlation_id).to eq(prepared.fetch(:event).correlation_id)
  end

  it "rejects a stale verification digest without activation or command completion" do
    prepared = ReleaseSetScenario.prepare(prefix: "activation-stale")
    integrations = ReleaseSetScenario.integrate_all(prepared, prefix: "activation-stale")
    verification = ReleaseSetScenario.record_verification(
      prepared, integrations:, prefix: "activation-stale"
    )
    input = {
      command_id: "cmd-release-activate-set-activation-stale",
      actor: { kind: "agent", id: "release-operator-1" },
      release_set_id: prepared.dig(:input, :release_set_id),
      verification_event: verification.fetch(:completion).data.verification_event.to_h,
      verification_digest: "sha256:#{'0' * 64}",
      activation_point: {
        kind: "configuration",
        environment: "production",
        external_reference: "configuration/activation-stale",
        state_digest: "sha256:#{'a' * 64}",
        producer: { name: "deployment-controller", version: "1.0.0" },
        run_id: "release-activation-stale",
        activated_at: "2026-08-24T21:00:00.000000Z"
      }
    }

    result = operation.call(input)

    expect(result.failure.code).to eq(:release_activation_verification_binding_stale)
    expect(ReleaseSetScenario.release_lifecycle_events(input.fetch(:release_set_id)).none? { _1.type == "ReleaseSetActivated" }).to be(true)
  end
end
