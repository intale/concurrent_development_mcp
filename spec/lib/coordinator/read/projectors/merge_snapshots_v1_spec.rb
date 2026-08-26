# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::MergeSnapshotsV1, :event_store, :read_model do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }

  it "serves an available not-found view during lag and converges idempotently" do
    candidate = CandidateScenario.submit(prefix: "merge-projection", build_context: false)
    input = {
      command_id: "cmd-register-merge-projection",
      actor: { kind: "agent", id: "integrator-1" },
      merge_snapshot_id: "MS-merge-projection",
      repository_id: candidate.dig(:input, :repository_id),
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

  it "serves the latest observed authorization without making freshness an availability gate" do
    registration = MergeSnapshotScenario.register(prefix: "merge-authorization-projection")
    verification = MergeSnapshotScenario.verify(
      registration,
      prefix: "merge-authorization-projection"
    )
    input = MergeSnapshotScenario.authorization_input(
      registration,
      verification,
      prefix: "merge-authorization-projection"
    )
    operation = Coordinator::Write::Operations::ExecuteRequestMergeAuthorization.new(
      event_store:
    )
    granted = operation.call(input).value!
    projector = described_class.new
    snapshot_stream = Coordinator::Write::StreamFactory.new.merge_snapshot(
      input.fetch(:merge_snapshot_id)
    )
    event_store.read(
      snapshot_stream,
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[
          MergeSnapshotRegistered
          MergeSnapshotVerificationSubmitted
          MergeSnapshotVerified
        ],
        maximum_count: 3,
        direction: :asc
      )
    ).each { projector.call(_1) }
    query = Coordinator::Read::Queries::MergeSnapshotGet.new

    before_authorization = query.call(merge_snapshot_id: input.fetch(:merge_snapshot_id)).value!
    expect(before_authorization.data.snapshot.latest_authorization).to be_nil

    granted_event = authorization_event(granted.data.authorization_id)
    projector.call(granted_event)
    projector.call(granted_event)
    observed_grant = query.call(merge_snapshot_id: input.fetch(:merge_snapshot_id)).value!
    expect(observed_grant.data.snapshot.latest_authorization).to have_attributes(
      authorization_id: granted.data.authorization_id,
      outcome: "granted"
    )

    denied_input = input.merge(
      command_id: "cmd-authorize-merge-authorization-projection-denied",
      target_base_observation: input.fetch(:target_base_observation).merge(commit_oid: "c" * 40)
    )
    denied = operation.call(denied_input).value!
    projector.call(authorization_event(denied.data.authorization_id))
    observed_denial = query.call(merge_snapshot_id: input.fetch(:merge_snapshot_id)).value!

    expect(observed_denial.data.snapshot.latest_authorization).to have_attributes(
      authorization_id: denied.data.authorization_id,
      outcome: "denied"
    )
    expect(observed_denial.data.snapshot.latest_authorization.evaluation.reasons.map(&:code)).to include(
      "target_base_binding_stale"
    )
    expect(Coordinator::Read::MergeAuthorization.count).to eq(2)
  end

  it "serves the snapshot during observation lag and converges idempotently" do
    registration = MergeSnapshotScenario.register(prefix: "merge-observation-projection")
    verification = MergeSnapshotScenario.verify(registration, prefix: "merge-observation-projection")
    authorization = MergeSnapshotScenario.authorize(
      registration,
      verification,
      prefix: "merge-observation-projection"
    )
    input = MergeSnapshotScenario.observation_input(
      registration,
      authorization,
      prefix: "merge-observation-projection"
    )
    Coordinator::Write::Operations::ExecuteRecordMergeObservation.new(event_store:).call(input).value!

    projector = described_class.new
    snapshot_id = input.fetch(:merge_snapshot_id)
    stream = Coordinator::Write::StreamFactory.new.merge_snapshot(snapshot_id)
    history = event_store.read_grouped(
      stream,
      Coordinator::Write::GroupedEventReadCriteria.new(
        event_types: %w[
          MergeSnapshotRegistered
          MergeSnapshotVerificationSubmitted
          MergeSnapshotVerified
          MergeObserved
        ],
        direction: :asc
      )
    )
    history.reject { _1.type == "MergeObserved" }.each { projector.call(_1) }
    query = Coordinator::Read::Queries::MergeSnapshotGet.new

    lagging = query.call(merge_snapshot_id: snapshot_id).value!.data.snapshot
    expect(lagging.observation).to be_nil

    observed = history.find { _1.type == "MergeObserved" }
    projector.call(observed)
    projector.call(observed)
    converged = query.call(merge_snapshot_id: snapshot_id).value!.data.snapshot
    expect(converged.observation).to have_attributes(
      target_after_commit_oid: registration.dig(:input, :merge_commit_oid),
      evidence_status: "attributed_unverified"
    )
    expect(Coordinator::Read::MergeSnapshot.count).to eq(1)
  end

  def authorization_event(authorization_id)
    event_store.read(
      Coordinator::Write::StreamFactory.new.merge_authorization(authorization_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[MergeAuthorizationGranted MergeAuthorizationDenied],
        maximum_count: 1,
        direction: :asc
      )
    ).sole
  end
end
