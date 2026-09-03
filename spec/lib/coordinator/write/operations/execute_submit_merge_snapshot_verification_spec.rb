# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteSubmitMergeSnapshotVerification, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:operation) { described_class.new(event_store:) }
  let(:streams) { Coordinator::Write::StreamFactory.new }

  it "records a qualifying assessment and verifies the exact snapshot atomically" do
    registration = MergeSnapshotScenario.register(prefix: "verify-pass")
    input = MergeSnapshotScenario.verification_input(registration, prefix: "verify-pass")

    result = operation.call(input)

    expect(result).to be_success
    expect(result.value!.data).to have_attributes(status: "verified", conclusion: "passed")
    events = verification_events(input.fetch(:merge_snapshot_id))
    expect(events.map(&:type)).to eq(
      %w[MergeSnapshotVerificationSubmitted MergeSnapshotVerified]
    )
    expect(events.map(&:stream_revision)).to eq([ 1, 2 ])
    expect(events.map(&:correlation_id).uniq).to contain_exactly(events.first.correlation_id)
    expect(events.last.data.dig("selected_verification", "event", "event_id")).to eq(events.first.id)
    expect(events.last.data.dig("snapshot", "event", "event_id")).to eq(registration.fetch(:event).id)
  end

  it "retains a non-passing assessment and permits a later exact pass" do
    registration = MergeSnapshotScenario.register(prefix: "verify-recovery")
    failed_input = MergeSnapshotScenario.verification_input(
      registration,
      prefix: "verify-recovery-failed",
      conclusion: "failed",
      findings: [ { code: "spec_failure", severity: "error", summary: "One example failed" } ]
    )
    passed_input = MergeSnapshotScenario.verification_input(
      registration,
      prefix: "verify-recovery-passed"
    )

    failed = operation.call(failed_input)
    passed = operation.call(passed_input)

    expect(failed.value!.data).to have_attributes(status: "failed")
    expect(passed.value!.data).to have_attributes(status: "verified")
    expect(verification_events(failed_input.fetch(:merge_snapshot_id)).map(&:type)).to eq(
      %w[
        MergeSnapshotVerificationSubmitted
        MergeSnapshotVerificationSubmitted
        MergeSnapshotVerified
      ]
    )
  end

  it "leaves replay ownership to the registered Command lifecycle and rejects duplicate evidence" do
    registration = MergeSnapshotScenario.register(prefix: "verify-replay")
    input = MergeSnapshotScenario.verification_input(
      registration,
      prefix: "verify-replay",
      conclusion: "inconclusive",
      findings: [ { code: "runner_lost", severity: "warning", summary: "Runner stopped" } ]
    )

    first = operation.call(input)
    replay = operation.call(input)
    duplicate = operation.call(input.merge(command_id: "cmd-verify-replay-duplicate"))

    expect(first).to be_success
    expect(replay.failure.code).to eq(:merge_snapshot_verification_already_submitted)
    expect(duplicate.failure.code).to eq(:merge_snapshot_verification_already_submitted)
    expect(verification_events(input.fetch(:merge_snapshot_id)).length).to eq(1)
  end

  it "rejects absent, stale, and terminal snapshot decisions without partial facts" do
    registration = MergeSnapshotScenario.register(prefix: "verify-denials")
    input = MergeSnapshotScenario.verification_input(registration, prefix: "verify-denials")
    absent = input.merge(
      command_id: "cmd-verify-absent",
      merge_snapshot_id: "MS-absent",
      binding: input.fetch(:binding).merge(
        snapshot_event: input.dig(:binding, :snapshot_event).merge(stream_id: "MS-absent")
      )
    )
    stale = input.merge(
      command_id: "cmd-verify-stale",
      binding: input.fetch(:binding).merge(snapshot_digest: "sha256:#{'f' * 64}")
    )

    expect(operation.call(absent).failure.code).to eq(:merge_snapshot_not_found)
    expect(operation.call(stale).failure.code).to eq(:merge_snapshot_verification_binding_stale)
    expect(operation.call(input)).to be_success
    terminal = input.merge(
      command_id: "cmd-verify-terminal",
      assessment: input.fetch(:assessment).merge(
        run_id: "verification-run-terminal",
        result_digest: "sha256:#{'4' * 64}"
      )
    )
    expect(operation.call(terminal).failure.code).to eq(:merge_snapshot_already_verified)
    expect(verification_events("MS-absent")).to be_empty
  end

  it "serializes competing qualifying assessments with one complete winner" do
    registration = MergeSnapshotScenario.register(prefix: "verify-race")
    inputs = %w[a b].map do |suffix|
      base = MergeSnapshotScenario.verification_input(
        registration,
        prefix: "verify-race-#{suffix}"
      )
      base.merge(
        assessment: base.fetch(:assessment).merge(result_digest: "sha256:#{suffix * 64}")
      )
    end

    results = inputs.map do |input|
      Thread.new { described_class.new(event_store:).call(input) }
    end.map(&:value)

    expect(results.count(&:success?)).to eq(1)
    expect(results.count(&:failure?)).to eq(1)
    expect(results.find(&:failure?).failure.code).to eq(:merge_snapshot_already_verified)
    expect(verification_events(registration.dig(:input, :merge_snapshot_id)).map(&:type)).to eq(
      %w[MergeSnapshotVerificationSubmitted MergeSnapshotVerified]
    )
  end

  def verification_events(snapshot_id)
    event_store.read(
      streams.merge_snapshot(snapshot_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[MergeSnapshotVerificationSubmitted MergeSnapshotVerified],
        maximum_count: 34,
        direction: :asc
      )
    )
  end
end
