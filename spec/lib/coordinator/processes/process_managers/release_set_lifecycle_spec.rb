# frozen_string_literal: true

RSpec.describe Coordinator::Processes::ProcessManagers::ReleaseSetLifecycle, :event_store do
  subject(:process_manager) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }

  it "requests one traced compensation after partial integration failure under redelivery" do
    prepared = ReleaseSetScenario.prepare(prefix: "lifecycle-compensation")
    observation = ReleaseSetScenario.observe_member(prepared, index: 0, prefix: "lifecycle-compensation")
    ReleaseSetScenario.record_integration(
      prepared, index: 0, prefix: "lifecycle-compensation", observation:
    )
    failure = ReleaseSetScenario.record_integration(
      prepared,
      index: 1,
      prefix: "lifecycle-compensation",
      failure: failure_evidence("lifecycle-compensation")
    )

    process_manager.call(failure.fetch(:event))
    process_manager.call(failure.fetch(:event))
    request = lifecycle(prepared).select { _1.type == "ReleaseSetCompensationRequested" }.sole
    payload = ReleaseSetScenario.load(request)

    expect(payload.successful_integrations.length).to eq(1)
    expect(payload.trigger_event).to eq(ReleaseSetScenario.reference(failure.fetch(:event)))
    step = process_step(
      source_event: failure.fetch(:event),
      step_name: "request-compensation",
      subject_id: prepared.dig(:input, :release_set_id)
    )
    expect(request.causation_id).to eq(step.id)
    expect(request.correlation_id).to eq(prepared.fetch(:event).correlation_id)
    expect(request.metadata.fetch("command_id")).to eq(step.data.fetch("target_command_id"))
  end

  it "completes an activated ReleaseSet exactly once under redelivery" do
    prepared = ReleaseSetScenario.prepare(prefix: "lifecycle-activated")
    integrations = ReleaseSetScenario.integrate_all(prepared, prefix: "lifecycle-activated")
    verification = ReleaseSetScenario.record_verification(
      prepared, integrations:, prefix: "lifecycle-activated"
    )
    activation = ReleaseSetScenario.record_activation(
      prepared, verification:, prefix: "lifecycle-activated"
    )

    process_manager.call(activation.fetch(:event))
    process_manager.call(activation.fetch(:event))
    completion = lifecycle(prepared).select { _1.type == "ReleaseSetCompleted" }.sole

    expect(ReleaseSetScenario.load(completion)).to have_attributes(
      outcome: "activated",
      source_event: ReleaseSetScenario.reference(activation.fetch(:event))
    )
    step = process_step(
      source_event: activation.fetch(:event),
      step_name: "complete-activated-release-set",
      subject_id: prepared.dig(:input, :release_set_id)
    )
    expect(completion.causation_id).to eq(step.id)
    expect(completion.correlation_id).to eq(prepared.fetch(:event).correlation_id)
    expect(completion.metadata.fetch("command_id")).to eq(step.data.fetch("target_command_id"))
  end

  it "requests compensation when exact composite verification fails after all integrations" do
    prepared = ReleaseSetScenario.prepare(prefix: "lifecycle-verification-failed")
    integrations = ReleaseSetScenario.integrate_all(
      prepared, prefix: "lifecycle-verification-failed"
    )
    verification = ReleaseSetScenario.record_verification(
      prepared,
      integrations:,
      prefix: "lifecycle-verification-failed",
      outcome: "failed",
      findings: [
        {
          code: "cross-repository-failure",
          severity: "error",
          summary: "Composite verification failed",
          repository_id: nil
        }
      ]
    )

    process_manager.call(verification.fetch(:event))
    request = lifecycle(prepared).select { _1.type == "ReleaseSetCompensationRequested" }.sole
    payload = ReleaseSetScenario.load(request)

    expect(payload).to have_attributes(
      trigger_kind: "release_verification_failed",
      trigger_event: ReleaseSetScenario.reference(verification.fetch(:event))
    )
    expect(payload.successful_integrations).to eq(integrations.map { _1.fetch(:completion).data.integration_event })
  end

  it "publishes one unique registration in the shared process-manager set" do
    registration = Coordinator::Processes::Subscriptions::ReleaseSetLifecycle.new(
      handler: process_manager,
      pull_interval: 0.1
    )

    expect(registration.definition.identity.to_h).to eq(
      set_name: "coordinator-process-managers-v1",
      subscription_name: "release-set-lifecycle-v1"
    )
    expect(registration.definition.options).to eq(
      filter: {
        streams: [ { context: "DevelopmentIntegration", stream_name: "ReleaseSet" } ],
        event_types: %w[
          RepositoryIntegrationRecorded
          ReleaseSetVerificationRecorded
          ReleaseSetActivated
        ]
      }
    )
  end

  private

  def lifecycle(prepared)
    ReleaseSetScenario.release_lifecycle_events(prepared.dig(:input, :release_set_id))
  end

  def process_step(source_event:, step_name:, subject_id:)
    ProcessStepExamples.event(
      event_store:,
      source_event:,
      process_name: "release-set-lifecycle",
      step_name:,
      subject_kind: "release-set",
      subject_id:
    )
  end

  def failure_evidence(prefix)
    {
      code: "deployment-failed",
      summary: "Ledger integration failed",
      producer: { name: "release-adapter", version: "1.0.0" },
      run_id: "release-failure-#{prefix}",
      result_digest: "sha256:#{'d' * 64}",
      occurred_at: "2026-08-24T21:30:00.000000Z"
    }
  end
end
