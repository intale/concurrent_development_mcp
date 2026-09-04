# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteSubmitMergeSnapshotVerification, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:operation) { described_class.new(event_store:) }
  let(:streams) { Coordinator::Write::StreamFactory.new }

  it "records one assessment and assigns it to the exact snapshot atomically" do
    registration = MergeSnapshotScenario.register(prefix: "verify-pass")
    input = MergeSnapshotScenario.verification_input(registration, prefix: "verify-pass")

    result = operation.call(input)

    expect(result).to be_success
    receipt = result.value!.data
    expect(receipt).to have_attributes(status: "unverified", conclusion: "passed", verified_event: nil)
    submission = submission_event(receipt.verification_id)
    assignments = snapshot_events(input.fetch(:merge_snapshot_id))
    expect(assignments.map(&:type)).to eq([ "MergeSnapshotVerificationAssigned" ])
    expect(submission.data).to eq(
      "verification_id" => receipt.verification_id,
      "merge_snapshot_id" => input.fetch(:merge_snapshot_id),
      "assessment" => stringify(input.fetch(:assessment))
    )
    expect(assignments.sole.data).to eq(
      "verification_id" => receipt.verification_id,
      "merge_snapshot_id" => input.fetch(:merge_snapshot_id)
    )
    expect(submission.metadata.fetch("verification_input_digest")).to eq(receipt.verification_input_digest)
    expect(assignments.sole.causation_id).to eq(submission.id)
    expect([ submission, assignments.sole ].map(&:correlation_id).uniq).to contain_exactly(submission.correlation_id)
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
    expect(passed.value!.data).to have_attributes(status: "unverified")
    expect(snapshot_events(failed_input.fetch(:merge_snapshot_id)).map(&:type)).to eq(
      %w[MergeSnapshotVerificationAssigned MergeSnapshotVerificationAssigned]
    )
    expect(submission_event(failed.value!.data.verification_id).data.dig("assessment", "conclusion")).to eq("failed")
    expect(submission_event(passed.value!.data.verification_id).data.dig("assessment", "conclusion")).to eq("passed")
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
    expect(snapshot_events(input.fetch(:merge_snapshot_id)).map(&:type)).to eq(
      [ "MergeSnapshotVerificationAssigned" ]
    )
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
    accepted = operation.call(input)
    verify_submission(accepted.value!.data)
    terminal = input.merge(
      command_id: "cmd-verify-terminal",
      assessment: input.fetch(:assessment).merge(
        run_id: "verification-run-terminal",
        result_digest: "sha256:#{'4' * 64}"
      )
    )
    expect(operation.call(terminal).failure.code).to eq(:merge_snapshot_already_verified)
    expect(snapshot_events("MS-absent")).to be_empty
  end

  it "serializes concurrent distinct assessments without losing either assignment" do
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

    expect(results).to all(be_success)
    expect(results.map { _1.value!.data.verification_id }.uniq.length).to eq(2)
    expect(snapshot_events(registration.dig(:input, :merge_snapshot_id)).map(&:stream_revision)).to eq([ 1, 2 ])
  end

  def verify_submission(receipt)
    command = Coordinator::Write::Commands::VerifyMergeSnapshot.new(
      command_id: Coordinator::Write::IdGenerator.new.uuid_v7,
      actor: { kind: "system", id: "spec-verifier" },
      merge_snapshot_id: receipt.merge_snapshot_id,
      verification_id: receipt.verification_id,
      policy_version: "merge-snapshot-verification/v1"
    )
    Coordinator::Write::Operations::ExecuteVerifyMergeSnapshot.new(event_store:).call(command)
  end

  def submission_event(verification_id)
    event_store.read(
      streams.merge_verification(verification_id),
      Coordinator::Write::EventQueries::MERGE_VERIFICATION_SUBMISSION
    ).sole
  end

  def snapshot_events(snapshot_id)
    event_store.read(
      streams.merge_snapshot(snapshot_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[
          MergeSnapshotVerificationAssigned
          MergeSnapshotVerificationSelected
          MergeSnapshotVerified
        ],
        maximum_count: 35,
        direction: :asc
      )
    )
  end

  def stringify(value)
    JSON.parse(JSON.generate(value))
  end
end
