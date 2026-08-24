# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::MergeSnapshotsV1, :event_store, :read_model do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }

  it "serves an available not-found view during lag and converges idempotently" do
    candidate = CandidateScenario.submit(prefix: "merge-projection", build_context: false)
    input = {
      command_id: "cmd-register-merge-projection",
      actor: { kind: "agent", id: "integrator-1" },
      merge_snapshot_id: "MS-merge-projection",
      repository_id: "billing",
      target_branch: "main",
      target_base_commit_oid: "a" * 40,
      ordered_candidates: [
        {
          candidate_id: candidate.dig(:input, :candidate_id),
          head_commit_oid: candidate.dig(:input, :head_commit_oid)
        }
      ],
      merge_commit_oid: "9" * 40,
      producer: { name: "git-merge", version: "2.47.0" },
      run_id: "run-merge-projection",
      produced_at: "2026-08-24T15:30:00.000001Z"
    }
    result = Coordinator::Write::Operations::ExecuteRegisterMergeSnapshot.new(event_store:).call(input)
    expect(result).to be_success

    query = Coordinator::Read::Queries::MergeSnapshotGet.new
    expect(query.call(merge_snapshot_id: input.fetch(:merge_snapshot_id)).value!.status).to eq("not_found")

    event = event_store.read(
      Coordinator::Write::StreamFactory.new.merge_snapshot(input.fetch(:merge_snapshot_id)),
      Coordinator::Write::EventQueries::MERGE_SNAPSHOT_REGISTRATION
    ).sole
    projector = described_class.new
    projector.call(event)
    projector.call(event)

    view = query.call(merge_snapshot_id: input.fetch(:merge_snapshot_id)).value!
    expect(view.status).to eq("ok")
    expect(view.data.snapshot).to have_attributes(
      merge_snapshot_id: input.fetch(:merge_snapshot_id),
      evidence_status: "attributed_unverified",
      merge_commit_oid: input.fetch(:merge_commit_oid)
    )
    expect(Coordinator::Read::MergeSnapshot.count).to eq(1)
  end

  it "serves each available verification observation and converges to verified" do
    registration = MergeSnapshotScenario.register(prefix: "merge-verification-projection")
    input = MergeSnapshotScenario.verification_input(
      registration,
      prefix: "merge-verification-projection"
    )
    result = Coordinator::Write::Operations::ExecuteSubmitMergeSnapshotVerification.new(
      event_store:
    ).call(input)
    expect(result).to be_success

    stream = Coordinator::Write::StreamFactory.new.merge_snapshot(input.fetch(:merge_snapshot_id))
    events = event_store.read(
      stream,
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[
          MergeSnapshotRegistered
          MergeSnapshotVerificationSubmitted
          MergeSnapshotVerified
        ],
        maximum_count: 3,
        direction: :asc
      )
    )
    projector = described_class.new
    query = Coordinator::Read::Queries::MergeSnapshotGet.new

    projector.call(events.fetch(0))
    expect(query.call(merge_snapshot_id: input.fetch(:merge_snapshot_id)).value!.data.snapshot.verification.status).to eq("unverified")

    projector.call(events.fetch(1))
    observed = query.call(merge_snapshot_id: input.fetch(:merge_snapshot_id)).value!.data.snapshot
    expect(observed.verification).to have_attributes(status: "unverified")
    expect(observed.verification.submissions.sole.assessment.conclusion).to eq("passed")

    projector.call(events.fetch(2))
    projector.call(events.fetch(2))
    converged = query.call(merge_snapshot_id: input.fetch(:merge_snapshot_id)).value!.data.snapshot
    expect(converged.verification).to have_attributes(status: "verified")
    expect(converged.verification.verified.selected_verification.verification_id).to eq(
      converged.verification.submissions.sole.verification_id
    )
    expect(Coordinator::Read::MergeSnapshot.count).to eq(1)
  end
end
