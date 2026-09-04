# frozen_string_literal: true

RSpec.describe Coordinator::Processes::ProcessManagers::MergeSnapshotVerification, :event_store do
  subject(:process_manager) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }

  it "selects and verifies one passing assessment exactly once under redelivery" do
    registration = MergeSnapshotScenario.register(prefix: "verification-process-pass")
    receipt = submit(registration, prefix: "verification-process-pass")
    source = submission_event(receipt.verification_id)

    process_manager.call(source)
    process_manager.call(source)

    terminal = snapshot_terminal(receipt.merge_snapshot_id)
    expect(terminal.map(&:type)).to eq(
      %w[MergeSnapshotVerificationSelected MergeSnapshotVerified]
    )
    expect(terminal.first.data).to eq(
      "merge_snapshot_id" => receipt.merge_snapshot_id,
      "verification_id" => receipt.verification_id
    )
    expect(terminal.last.data).to eq("merge_snapshot_id" => receipt.merge_snapshot_id)
    expect(terminal.last.metadata.fetch("verification_digest")).to match(/\Asha256:[0-9a-f]{64}\z/)

    step = process_step(source, receipt.merge_snapshot_id)
    expect(terminal.first.causation_id).to eq(step.id)
    expect(terminal.last.causation_id).to eq(terminal.first.id)
    expect([ source, step, *terminal ].map(&:correlation_id).uniq).to contain_exactly(source.correlation_id)
    expect(terminal.map { _1.metadata.fetch("command_id") }.uniq).to contain_exactly(
      step.data.fetch("target_command_id")
    )
  end

  it "records no verification fact for a non-passing assessment" do
    registration = MergeSnapshotScenario.register(prefix: "verification-process-fail")
    receipt = submit(
      registration,
      prefix: "verification-process-fail",
      conclusion: "failed",
      findings: [ { code: "spec_failure", severity: "error", summary: "One example failed" } ]
    )
    source = submission_event(receipt.verification_id)

    process_manager.call(source)
    process_manager.call(source)

    expect(snapshot_terminal(receipt.merge_snapshot_id)).to be_empty
    expect(process_step(source, receipt.merge_snapshot_id)).to be_present
  end

  it "keeps the first selected passing assessment when another passing assessment is delivered" do
    registration = MergeSnapshotScenario.register(prefix: "verification-process-choice")
    first = submit(registration, prefix: "verification-process-choice-a")
    second = submit(registration, prefix: "verification-process-choice-b")

    process_manager.call(submission_event(first.verification_id))
    process_manager.call(submission_event(second.verification_id))

    selected = snapshot_terminal(first.merge_snapshot_id).first
    expect(selected.data.fetch("verification_id")).to eq(first.verification_id)
  end

  it "publishes one unique registration in the shared process-manager set" do
    registration = Coordinator::Processes::Subscriptions::MergeSnapshotVerification.new(
      handler: process_manager,
      pull_interval: 0.1
    )

    expect(registration.definition.identity.to_h).to eq(
      set_name: Coordinator::Processes::Subscriptions::ProcessManagerSet::SET_NAME,
      subscription_name: "merge-snapshot-verification-v1"
    )
    expect(registration.definition.options).to eq(
      filter: {
        streams: [ { context: "DevelopmentIntegration", stream_name: "MergeVerification" } ],
        event_types: [ "MergeSnapshotVerificationSubmitted" ]
      }
    )
  end

  private

  def submit(registration, prefix:, conclusion: "passed", findings: [])
    input = MergeSnapshotScenario.verification_input(
      registration,
      prefix:,
      conclusion:,
      findings:
    )
    result = Coordinator::Write::Operations::ExecuteSubmitMergeSnapshotVerification.new(
      event_store:
    ).call(input)
    raise result.failure.inspect if result.failure?

    result.value!.data
  end

  def submission_event(verification_id)
    event_store.read(
      streams.merge_verification(verification_id),
      Coordinator::Write::EventQueries::MERGE_VERIFICATION_SUBMISSION
    ).sole
  end

  def snapshot_terminal(merge_snapshot_id)
    event_store.read(
      streams.merge_snapshot(merge_snapshot_id),
      Coordinator::Write::EventQueries::MERGE_SNAPSHOT_VERIFIED
    )
  end

  def process_step(source, merge_snapshot_id)
    ProcessStepExamples.event(
      event_store:,
      source_event: source,
      process_name: "merge-snapshot-verification",
      step_name: "verify",
      subject_kind: "merge-snapshot",
      subject_id: merge_snapshot_id
    )
  end
end
