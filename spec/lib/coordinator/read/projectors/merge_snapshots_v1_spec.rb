# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::MergeSnapshotsV1, :read_model do
  subject(:projector) { described_class.new }

  let(:repository) { Coordinator::Read::Repositories::MergeSnapshots.new }
  let(:merge_snapshot_id) { "MS-merge-projection" }
  let(:repository_id) { "018f0f4d-4e45-7abc-8def-000000000401" }
  let(:candidate_id) { "CAN-merge-projection" }
  let(:correlation_id) { SecureRandom.uuid_v7 }

  it "serves an available not-found view during lag and converges idempotently" do
    event = registration_event
    query = Coordinator::Read::Queries::MergeSnapshotGet.new

    expect(query.call(merge_snapshot_id:).value!.status).to eq("not_found")

    projector.call(event)
    projector.call(event)

    view = query.call(merge_snapshot_id:).value!
    expect(view.status).to eq("ok")
    expect(view.data.snapshot).to have_attributes(
      merge_snapshot_id:,
      evidence_status: "attributed_unverified",
      merge_commit_oid: "9" * 40
    )
    expect(Coordinator::Read::MergeSnapshot.count).to eq(1)
  end

  it "serves each available verification observation and converges to verified" do
    registered, submitted, verified = verification_events

    projector.call(registered)
    expect(repository.fetch(merge_snapshot_id).verification.status).to eq("unverified")

    projector.call(submitted)
    observed = repository.fetch(merge_snapshot_id)
    expect(observed.verification).to have_attributes(status: "unverified")
    expect(observed.verification.submissions.sole.assessment.conclusion).to eq("passed")

    projector.call(verified)
    projector.call(verified)
    converged = repository.fetch(merge_snapshot_id)
    expect(converged.verification).to have_attributes(status: "verified")
    expect(converged.verification.verified.selected_verification.verification_id).to eq(
      converged.verification.submissions.sole.verification_id
    )
    expect(Coordinator::Read::MergeSnapshot.count).to eq(1)
  end

  it "serves the latest observed authorization without making freshness an availability gate" do
    registered, submitted, verified = verification_events
    [ registered, submitted, verified ].each { projector.call(_1) }

    expect(repository.fetch(merge_snapshot_id).latest_authorization).to be_nil

    granted = authorization_event(outcome: "granted", position: 400)
    projector.call(granted)
    projector.call(granted)
    expect(repository.fetch(merge_snapshot_id).latest_authorization).to have_attributes(
      authorization_id: granted.stream.stream_id,
      outcome: "granted"
    )

    denied = authorization_event(outcome: "denied", position: 500)
    projector.call(denied)
    observed = repository.fetch(merge_snapshot_id).latest_authorization
    expect(observed).to have_attributes(
      authorization_id: denied.stream.stream_id,
      outcome: "denied"
    )
    expect(observed.evaluation.reasons.map(&:code)).to contain_exactly("target_base_binding_stale")
    expect(Coordinator::Read::MergeAuthorization.count).to eq(2)
  end

  it "serves the snapshot during observation lag and converges idempotently" do
    registered, submitted, verified = verification_events
    [ registered, submitted, verified ].each { projector.call(_1) }

    expect(repository.fetch(merge_snapshot_id).observation).to be_nil

    observed = observation_event(authorization_event(outcome: "granted", position: 400))
    projector.call(observed)
    projector.call(observed)

    observation = repository.fetch(merge_snapshot_id).observation
    expect(observation).to have_attributes(
      target_after_commit_oid: "9" * 40,
      evidence_status: "attributed_unverified"
    )
    expect(Coordinator::Read::MergeSnapshot.count).to eq(1)
  end

  def registration_event
    @registration_event ||= snapshot_event(registration_payload, revision: 0, position: 100)
  end

  def registration_payload
    @registration_payload ||= Coordinator::Write::Events::MergeSnapshotRegisteredV1.new(
      merge_snapshot_id:,
      repository_id:,
      target_branch: "main",
      object_format: "sha1",
      target_base_commit_oid: "a" * 40,
      ordered_candidates: [
        Coordinator::Write::MergeSnapshots::CandidateMemberV1.new(
          candidate_id:,
          change_set_id: "CS-merge-projection",
          work_item_id: "WI-merge-projection",
          attempt_id: "ATT-merge-projection",
          repository_id:,
          target_branch: "main",
          object_format: "sha1",
          base_commit_oid: "a" * 40,
          head_commit_oid: "b" * 40,
          manifest_digest: digest("1"),
          candidate_event: source_reference("CandidateSubmitted", "Candidate", candidate_id, 0),
          manifest_event: source_reference("CandidateManifestDeclared", "Candidate", candidate_id, 1)
        )
      ],
      merge_commit_oid: "9" * 40,
      producer: Coordinator::Write::MergeSnapshots::ProducerV1.new(name: "git-merge", version: "2.47.0"),
      run_id: "run-merge-projection",
      produced_at: "2026-08-30T12:00:00.000000Z",
      snapshot_digest: digest("2"),
      policy_version: "merge-snapshot-registration/v1",
      evidence_status: "attributed_unverified",
      registered_at: "2026-08-30T12:00:01.000000Z"
    )
  end

  def verification_events
    @verification_events ||= begin
      registered = registration_event
      submitted = snapshot_event(
        Coordinator::Write::Events::MergeSnapshotVerificationSubmittedV1.new(
          merge_snapshot_id:,
          snapshot: snapshot_evidence(registered),
          verification_id: "018f0f4d-4e45-7abc-8def-000000000402",
          policy_version: "merge-snapshot-verification/v1",
          assessment: verification_assessment,
          verification_input_digest: digest("3"),
          submitted_at: "2026-08-30T12:01:00.000000Z"
        ),
        revision: 1,
        position: 200,
        causation_id: registered.id
      )
      verified = snapshot_event(
        Coordinator::Write::Events::MergeSnapshotVerifiedV1.new(
          merge_snapshot_id:,
          snapshot: snapshot_evidence(registered),
          policy_version: "merge-snapshot-verification/v1",
          selected_verification: Coordinator::Write::MergeSnapshotVerifications::VerificationDecisionReferenceV1.new(
            verification_id: submitted.data.fetch("verification_id"),
            evidence_kind: "combined_tests",
            conclusion: "passed",
            result_digest: digest("6"),
            verification_input_digest: digest("3"),
            event: event_reference(submitted)
          ),
          verification_digest: digest("7"),
          verified_at: "2026-08-30T12:02:00.000000Z"
        ),
        revision: 2,
        position: 300,
        causation_id: submitted.id
      )
      [ registered, submitted, verified ]
    end
  end

  def verification_assessment
    Coordinator::Write::MergeSnapshotVerifications::AssessmentV1.new(
      evidence_kind: "combined_tests",
      producer: Coordinator::Write::MergeSnapshotVerifications::ProducerV1.new(
        name: "project-tests",
        version: "1.0"
      ),
      run_id: "run-verification-projection",
      test_suite_digest: digest("4"),
      environment_digest: digest("5"),
      result_digest: digest("6"),
      conclusion: "passed",
      findings: [],
      produced_at: "2026-08-30T12:00:30.000000Z"
    )
  end

  def snapshot_evidence(registered)
    Coordinator::Write::MergeSnapshotVerifications::SnapshotEvidenceV1.new(
      snapshot: registration_payload,
      event: event_reference(registered)
    )
  end

  def authorization_event(outcome:, position:)
    authorization_id = outcome == "granted" ?
      "018f0f4d-4e45-7abc-8def-000000000403" :
      "018f0f4d-4e45-7abc-8def-000000000404"
    payload_class = outcome == "granted" ?
      Coordinator::Write::Events::MergeAuthorizationGrantedV1 :
      Coordinator::Write::Events::MergeAuthorizationDeniedV1
    reasons =
      if outcome == "granted"
        []
      else
        [
          Coordinator::Write::MergeAuthorizations::ReasonV1.new(
            code: "target_base_binding_stale",
            message: "The target branch no longer matches the snapshot base.",
            candidate_id: nil,
            work_item_id: nil,
            dependency_id: nil,
            source_candidate_id: nil,
            target_candidate_id: nil,
            obligation_id: nil,
            obligation_status: nil,
            expected_reference: nil,
            observed_reference: nil,
            expected_digest: nil,
            observed_digest: nil,
            expected_oid: "a" * 40,
            observed_oid: "c" * 40
          )
        ]
      end
    payload = payload_class.new(
      authorization_id:,
      merge_snapshot_id:,
      policy_version: "merge-authorization/v1",
      snapshot_binding: snapshot_binding,
      expected_impact_policy: nil,
      evaluation: authorization_evaluation(reasons:, observed_oid: outcome == "granted" ? "a" * 40 : "c" * 40),
      input_digest: digest(outcome == "granted" ? "8" : "a"),
      decision_digest: digest(outcome == "granted" ? "9" : "b"),
      decided_at: outcome == "granted" ? "2026-08-30T12:03:00.000000Z" : "2026-08-30T12:04:00.000000Z"
    )
    ProjectionEventFactory.build(
      payload:,
      stream: Coordinator::Write::StreamFactory.new.merge_authorization(authorization_id),
      stream_revision: 0,
      global_position: position,
      policy_version: "merge-authorization/v1",
      command_id: "cmd-authorization-#{outcome}",
      correlation_id:
    )
  end

  def authorization_evaluation(reasons:, observed_oid:)
    Coordinator::Write::MergeAuthorizations::EvaluationV1.new(
      merge_snapshot_id:,
      snapshot: nil,
      target_base_observation: Coordinator::Write::MergeAuthorizations::TargetBaseObservationV1.new(
        repository_id:,
        target_branch: "main",
        object_format: "sha1",
        commit_oid: observed_oid,
        observer: Coordinator::Write::MergeSnapshotVerifications::ProducerV1.new(
          name: "git-observer",
          version: "2.47.0"
        ),
        run_id: "run-authorization-projection",
        observed_at: "2026-08-30T12:02:30.000000Z"
      ),
      current_policy: nil,
      candidates: [],
      work_item_progress: [],
      obligations: [],
      reasons:
    )
  end

  def observation_event(authorization)
    payload = Coordinator::Write::Events::MergeObservedV1.new(
      merge_snapshot_id:,
      authorization_event: event_reference(authorization),
      authorization_decision_digest: digest("9"),
      snapshot_binding:,
      repository_id:,
      target_branch: "main",
      object_format: "sha1",
      target_before_commit_oid: "a" * 40,
      target_after_commit_oid: "9" * 40,
      observer: Coordinator::Write::MergeObservations::ObserverV1.new(name: "git-observer", version: "2.47.0"),
      run_id: "run-observation-projection",
      observed_at: "2026-08-30T12:05:00.000000Z",
      observation_digest: digest("c"),
      policy_version: "merge-observation/v1",
      evidence_status: "attributed_unverified",
      recorded_at: "2026-08-30T12:05:01.000000Z"
    )
    snapshot_event(
      payload,
      revision: 3,
      position: 600,
      policy_version: "merge-observation/v1",
      causation_id: authorization.id
    )
  end

  def snapshot_binding
    registered, _submitted, verified = verification_events
    Coordinator::Write::MergeAuthorizations::SnapshotBindingV1.new(
      registration_event: event_reference(registered),
      snapshot_digest: digest("2"),
      verification_event: event_reference(verified),
      verification_digest: digest("7")
    )
  end

  def snapshot_event(payload, revision:, position:, policy_version: nil, causation_id: nil)
    ProjectionEventFactory.build(
      payload:,
      stream: Coordinator::Write::StreamFactory.new.merge_snapshot(merge_snapshot_id),
      stream_revision: revision,
      global_position: position,
      policy_version: policy_version || payload.policy_version,
      command_id: "cmd-merge-snapshot-projection",
      correlation_id:,
      causation_id:
    )
  end

  def source_reference(type, stream_name, stream_id, revision)
    Coordinator::Write::EventReference.new(
      event_id: SecureRandom.uuid_v7,
      type:,
      stream_context: "DevelopmentCoordination",
      stream_name:,
      stream_id:,
      stream_revision: revision
    )
  end

  def event_reference(event)
    Coordinator::Write::EventReference.new(
      event_id: event.id,
      type: event.type,
      stream_context: event.stream.context,
      stream_name: event.stream.stream_name,
      stream_id: event.stream.stream_id,
      stream_revision: event.stream_revision
    )
  end

  def digest(character)
    "sha256:#{character * 64}"
  end
end
