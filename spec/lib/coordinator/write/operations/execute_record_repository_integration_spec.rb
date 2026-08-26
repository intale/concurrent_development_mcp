# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteRecordRepositoryIntegration, :event_store do
  subject(:operation) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }

  it "records exact external observations in member order, preserves the ReleaseSet trace, and replays" do
    prepared = ReleaseSetScenario.prepare(prefix: "integration-success")
    first_observation = ReleaseSetScenario.observe_member(prepared, index: 0, prefix: "integration-success")
    input = successful_input(prepared, first_observation, index: 0, prefix: "integration-success")

    first = operation.call(input).value!
    replay = operation.call(input).value!
    events = lifecycle_events(prepared)
    integration = events.last
    payload = ReleaseSetScenario.load(integration)

    expect(replay).to eq(first)
    expect(payload).to have_attributes(
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      member_position: 1,
      attempt_number: 1,
      outcome: "integrated",
      evidence_status: "attributed_unverified"
    )
    expect(integration.correlation_id).to eq(prepared.fetch(:event).correlation_id)
    expect(integration.markers).to include(
      "release-set:REL-integration-success",
      "repository:#{RepositoryScenario::DEFAULT_REPOSITORY_ID}",
      "release-integration-outcome:integrated"
    )
    expect(lifecycle_events(prepared).count { _1.type == "RepositoryIntegrationRecorded" }).to eq(1)
  end

  it "denies a later member until every prior member has integrated" do
    prepared = ReleaseSetScenario.prepare(prefix: "integration-order")
    observation = ReleaseSetScenario.observe_member(prepared, index: 1, prefix: "integration-order")

    result = operation.call(successful_input(prepared, observation, index: 1, prefix: "integration-order"))

    expect(result.failure.code).to eq(:release_integration_out_of_order)
    expect(lifecycle_events(prepared).count { _1.type == "RepositoryIntegrationRecorded" }).to eq(0)
  end

  it "keeps retry possible after a first-member failure and records a later successful attempt" do
    prepared = ReleaseSetScenario.prepare(prefix: "integration-retry")
    failed = ReleaseSetScenario.record_integration(
      prepared,
      index: 0,
      prefix: "integration-failed",
      failure: failure_evidence
    )
    observation = ReleaseSetScenario.observe_member(prepared, index: 0, prefix: "integration-retry")
    succeeded = ReleaseSetScenario.record_integration(
      prepared,
      index: 0,
      prefix: "integration-retry",
      observation:
    )

    expect(failed.fetch(:payload)).to have_attributes(outcome: "failed", attempt_number: 1)
    expect(succeeded.fetch(:payload)).to have_attributes(outcome: "integrated", attempt_number: 2)
  end

  it "rejects an observation whose exact evidence does not match the prepared member" do
    prepared = ReleaseSetScenario.prepare(prefix: "integration-mismatch")
    observation = ReleaseSetScenario.observe_member(prepared, index: 0, prefix: "integration-mismatch")
    input = successful_input(prepared, observation, index: 0, prefix: "integration-mismatch")

    result = operation.call(input.merge(observation_digest: "sha256:#{'0' * 64}"))

    expect(result.failure.code).to eq(:release_integration_observation_mismatch)
    expect(lifecycle_events(prepared).count { _1.type == "RepositoryIntegrationRecorded" }).to eq(0)
  end

  it "closes repository integration after activation" do
    prepared = ReleaseSetScenario.prepare(prefix: "integration-after-activation")
    integrations = ReleaseSetScenario.integrate_all(
      prepared, prefix: "integration-after-activation"
    )
    verification = ReleaseSetScenario.record_verification(
      prepared, integrations:, prefix: "integration-after-activation"
    )
    ReleaseSetScenario.record_activation(
      prepared, verification:, prefix: "integration-after-activation"
    )
    integration = integrations.first.fetch(:payload)
    input = {
      command_id: "cmd-release-integrate-after-activation",
      actor: { kind: "agent", id: "release-integrator-1" },
      release_set_id: prepared.dig(:input, :release_set_id),
      repository_id: integration.repository_id,
      attempt_id: "release-attempt-after-activation",
      outcome: "integrated",
      merge_observation_event: integration.merge_observation_event.to_h,
      observation_digest: integration.observation_digest,
      failure: nil
    }

    result = operation.call(input)

    expect(result.failure.code).to eq(:release_set_already_activated)
  end

  it "closes repository integration after compensation is requested" do
    prepared = ReleaseSetScenario.prepare(prefix: "integration-after-compensation")
    observation = ReleaseSetScenario.observe_member(
      prepared, index: 0, prefix: "integration-after-compensation"
    )
    ReleaseSetScenario.record_integration(
      prepared, index: 0, prefix: "integration-after-compensation", observation:
    )
    failure = ReleaseSetScenario.record_integration(
      prepared,
      index: 1,
      prefix: "integration-after-compensation-failed",
      failure: failure_evidence
    )
    Coordinator::Processes::ProcessManagers::ReleaseSetLifecycle.new(event_store:).call(
      failure.fetch(:event)
    )
    input = failure.fetch(:input).merge(
      command_id: "cmd-release-integrate-after-compensation",
      attempt_id: "release-attempt-after-compensation"
    )

    result = operation.call(input)

    expect(result.failure.code).to eq(:release_set_compensation_requested)
  end

  def successful_input(prepared, observation, index:, prefix:)
    member = prepared.fetch(:payload).ordered_members.fetch(index)
    {
      command_id: "cmd-release-integrate-#{prefix}-#{index + 1}",
      actor: { kind: "agent", id: "release-integrator-1" },
      release_set_id: prepared.dig(:input, :release_set_id),
      repository_id: member.repository_id,
      attempt_id: "release-attempt-#{prefix}-#{index + 1}",
      outcome: "integrated",
      merge_observation_event: observation.fetch(:completion).data.observation_event.to_h,
      observation_digest: observation.fetch(:payload).observation_digest,
      failure: nil
    }
  end

  def failure_evidence
    {
      code: "merge_conflict",
      summary: "The external integration reported a merge conflict.",
      producer: { name: "release-adapter", version: "1.0.0" },
      run_id: "failed-integration-run-1",
      result_digest: "sha256:#{'d' * 64}",
      occurred_at: "2026-08-24T19:30:00.000000Z"
    }
  end

  def lifecycle_events(prepared)
    ReleaseSetScenario.release_lifecycle_events(prepared.dig(:input, :release_set_id))
  end
end
