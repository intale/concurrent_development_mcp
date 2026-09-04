# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteRecordReleaseSetActivation, :event_store do
  subject(:operation) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }

  it "records an exact attributed activation and rejects a second direct execution" do
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

    expect(replay.failure.code).to eq(:release_set_already_activated)
    expect(payload).to have_attributes(
      release_set_id: input.fetch(:release_set_id),
      change_set_id: prepared.fetch(:completion).data.change_set_id,
      activation_point: Coordinator::Write::ReleaseSets::ActivationPointV2.new(input.fetch(:activation_point))
    )
    expect(activation.metadata).to include(
      "verification_digest" => verification.fetch(:completion).data.verification_digest,
      "policy_version" => "release-set-activation/v1"
    )
    expect(activation.data).not_to have_key("recorded_at")
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
        run_id: "release-activation-stale"
      }
    }

    result = operation.call(input)

    expect(result.failure.code).to eq(:release_activation_verification_binding_stale)
    expect(ReleaseSetScenario.release_lifecycle_events(input.fetch(:release_set_id)).none? { _1.type == "ReleaseSetActivated" }).to be(true)
  end
end
