# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::MergeSnapshotsV1, :read_model do
  subject(:projector) { described_class.new(registration_loader:) }

  let(:repository) { Coordinator::Read::Repositories::MergeSnapshots.new }
  let(:merge_snapshot_id) { "MS-merge-projection" }
  let(:repository_id) { "018f0f4d-4e45-7abc-8def-000000000401" }
  let(:candidate_id) { "CAN-merge-projection" }
  let(:verification_id) { "018f0f4d-4e45-7abc-8def-000000000402" }
  let(:correlation_id) { SecureRandom.uuid_v7 }
  let(:registration_loader) { constant_loader(registration_view) }

  it "serves an available not-found view during lag and converges idempotently" do
    query = Coordinator::Read::Queries::MergeSnapshotGet.new
    expect(query.call(merge_snapshot_id:).value!.status).to eq("not_found")

    projector.call(registration_event)
    projector.call(registration_event)

    view = query.call(merge_snapshot_id:).value!
    expect(view.status).to eq("ok")
    expect(view.data.snapshot).to have_attributes(
      merge_snapshot_id:,
      producer: "git-merge",
      evidence_status: "attributed_unverified",
      merge_commit_oid: "9" * 40
    )
    expect(Coordinator::Read::MergeSnapshot.count).to eq(1)
  end

  it "converges through submitted, assigned, selected, and verified facts" do
    projector.call(registration_event)
    projector.call(verification_submission_event)
    projector.call(verification_assignment_event)

    observed = repository.fetch(merge_snapshot_id)
    expect(observed.verification).to have_attributes(status: "unverified")
    expect(observed.verification.submissions.sole.assessment.conclusion).to eq("passed")

    projector.call(verification_selection_event)
    expect(repository.fetch(merge_snapshot_id).verification.verified).to be_nil

    projector.call(verified_event)
    projector.call(verified_event)
    converged = repository.fetch(merge_snapshot_id)
    expect(converged.verification).to have_attributes(status: "verified")
    expect(converged.verification.verified.selected_verification.verification_id).to eq(verification_id)
    expect(converged.verification.verified.verification_digest).to eq(digest("7"))
  end

  it "serves the latest exact authorization without imposing a freshness gate" do
    project_verified_snapshot
    expect(repository.fetch(merge_snapshot_id).latest_authorization).to be_nil

    granted = authorization_event(outcome: "granted", position: 400)
    projector.call(granted)
    projector.call(granted)
    expect(repository.fetch(merge_snapshot_id).latest_authorization).to have_attributes(
      authorization_id: granted.stream.stream_id,
      outcome: "granted",
      decision_digest: digest("9")
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

  it "keeps the snapshot available while the observation link lags, then converges idempotently" do
    project_verified_snapshot
    authorization = authorization_event(outcome: "granted", position: 400)
    projector.call(authorization)

    observed, linked = observation_events(authorization)
    projector.call(observed)
    expect(repository.fetch(merge_snapshot_id).observation).to be_nil

    projector.call(linked)
    projector.call(linked)
    observation = repository.fetch(merge_snapshot_id).observation
    expect(observation).to have_attributes(
      target_after_commit_oid: "9" * 40,
      observer: "git-observer",
      evidence_status: "attributed_unverified",
      authorization_event: event_reference(authorization)
    )
  end

  def project_verified_snapshot
    [
      registration_event,
      verification_submission_event,
      verification_assignment_event,
      verification_selection_event,
      verified_event
    ].each { projector.call(_1) }
  end

  def registration_view
    Coordinator::Read::MergeSnapshotRegistrationViewV2.new(
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
          candidate_event: source_reference("CandidateSubmitted", "Candidate", candidate_id, 9),
          manifest_event: source_reference("CandidateChangeManifestCaptured", "Candidate", candidate_id, 7)
        )
      ],
      merge_commit_oid: "9" * 40,
      producer: "git-merge",
      run_id: "run-merge-projection",
      produced_at: "2026-08-30T12:00:00.000000Z",
      snapshot_digest: digest("2"),
      policy_version: "merge-snapshot-registration/v1",
      evidence_status: "attributed_unverified"
    )
  end

  def registration_event
    @registration_event ||= snapshot_event(
      Coordinator::Write::Events::MergeSnapshotRegisteredV2.new(
        merge_snapshot_id:,
        repository_id:,
        target_branch: "main",
        object_format: "sha1",
        target_base_commit_oid: "a" * 40,
        merge_commit_oid: "9" * 40,
        ordered_candidates: [ candidate_id ],
        producer: "git-merge",
        run_id: "run-merge-projection",
        produced_at: "2026-08-30T12:00:00.000000Z"
      ),
      revision: 0,
      position: 100,
      metadata: Coordinator::Write::Metadata::MergeSnapshotV2.new(
        **metadata_attributes("merge-snapshot-registration/v1", actor_kind: "agent", actor_id: "agent-a"),
        snapshot_digest: digest("2")
      )
    )
  end

  def verification_submission_event
    @verification_submission_event ||= projection_event(
      Coordinator::Write::Events::MergeSnapshotVerificationSubmittedV2.new(
        verification_id:,
        merge_snapshot_id:,
        assessment: verification_assessment
      ),
      stream: Coordinator::Write::StreamFactory.new.merge_verification(verification_id),
      revision: 0,
      position: 200,
      metadata: Coordinator::Write::Metadata::MergeSnapshotVerificationV2.new(
        **metadata_attributes("merge-snapshot-verification/v1", actor_kind: "agent", actor_id: "agent-a"),
        verification_input_digest: digest("3")
      )
    )
  end

  def verification_assignment_event
    @verification_assignment_event ||= snapshot_event(
      Coordinator::Write::Events::MergeSnapshotVerificationAssignedV1.new(
        verification_id:,
        merge_snapshot_id:
      ),
      revision: 1,
      position: 201,
      policy_version: "merge-snapshot-verification/v1",
      actor_kind: "agent",
      actor_id: "agent-a"
    )
  end

  def verification_selection_event
    @verification_selection_event ||= snapshot_event(
      Coordinator::Write::Events::MergeSnapshotVerificationSelectedV1.new(
        merge_snapshot_id:,
        verification_id:
      ),
      revision: 2,
      position: 300,
      policy_version: "merge-snapshot-verification/v1",
      actor_kind: "system",
      actor_id: "merge-snapshot-verification"
    )
  end

  def verified_event
    @verified_event ||= snapshot_event(
      Coordinator::Write::Events::MergeSnapshotVerifiedV2.new(merge_snapshot_id:),
      revision: 3,
      position: 301,
      metadata: Coordinator::Write::Metadata::MergeSnapshotVerifiedV2.new(
        **metadata_attributes(
          "merge-snapshot-verification/v1",
          actor_kind: "system",
          actor_id: "merge-snapshot-verification"
        ),
        verification_digest: digest("7")
      )
    )
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

  def authorization_event(outcome:, position:)
    authorization_id = outcome == "granted" ?
      "018f0f4d-4e45-7abc-8def-000000000403" :
      "018f0f4d-4e45-7abc-8def-000000000404"
    payload_class = outcome == "granted" ?
      Coordinator::Write::Events::MergeAuthorizationGrantedV2 :
      Coordinator::Write::Events::MergeAuthorizationDeniedV2
    reasons = outcome == "granted" ? [] : [ stale_target_reason ]
    payload = payload_class.new(
      authorization_id:,
      merge_snapshot_id:,
      snapshot_binding:,
      evaluation: authorization_evaluation(
        reasons:,
        observed_oid: outcome == "granted" ? "a" * 40 : "c" * 40
      )
    )
    ProjectionEventFactory.build(
      payload:,
      stream: Coordinator::Write::StreamFactory.new.merge_authorization(authorization_id),
      stream_revision: 0,
      global_position: position,
      policy_version: "merge-authorization/v1",
      metadata: Coordinator::Write::Metadata::MergeAuthorizationV2.new(
        **metadata_attributes("merge-authorization/v1", actor_kind: "agent", actor_id: "agent-a"),
        decision_digest: digest(outcome == "granted" ? "9" : "b"),
        expected_impact_policy: nil,
        input_digest: digest(outcome == "granted" ? "8" : "a")
      ),
      command_id: "cmd-authorization-#{outcome}",
      correlation_id:
    )
  end

  def stale_target_reason
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

  def observation_events(authorization)
    observed = snapshot_event(
      Coordinator::Write::Events::MergeObservedV2.new(
        merge_snapshot_id:,
        snapshot_binding:,
        repository_id:,
        target_branch: "main",
        object_format: "sha1",
        target_before_commit_oid: "a" * 40,
        target_after_commit_oid: "9" * 40,
        observer: "git-observer",
        run_id: "run-observation-projection",
        observed_at: "2026-08-30T12:05:00.000000Z"
      ),
      revision: 4,
      position: 600,
      metadata: Coordinator::Write::Metadata::MergeObservationV2.new(
        **metadata_attributes("merge-observation/v1", actor_kind: "agent", actor_id: "agent-a"),
        authorization_decision_digest: digest("9"),
        observation_digest: digest("c")
      ),
      causation_id: authorization.id
    )
    linked = snapshot_event(
      Coordinator::Write::Events::MergeObservationAuthorizationLinkedV1.new(
        merge_snapshot_id:,
        authorization_id: authorization.stream.stream_id,
        authorization_event: event_reference(authorization)
      ),
      revision: 5,
      position: 601,
      policy_version: "merge-observation/v1",
      actor_kind: "agent",
      actor_id: "agent-a",
      causation_id: observed.id
    )
    [ observed, linked ]
  end

  def snapshot_binding
    Coordinator::Write::MergeAuthorizations::SnapshotBindingV1.new(
      registration_event: event_reference(registration_event),
      snapshot_digest: digest("2"),
      verification_event: event_reference(verified_event),
      verification_digest: digest("7")
    )
  end

  def snapshot_event(
    payload,
    revision:,
    position:,
    policy_version: nil,
    actor_kind: "agent",
    actor_id: "agent-a",
    metadata: nil,
    causation_id: nil
  )
    projection_event(
      payload,
      stream: Coordinator::Write::StreamFactory.new.merge_snapshot(merge_snapshot_id),
      revision:,
      position:,
      policy_version:,
      actor_kind:,
      actor_id:,
      metadata:,
      causation_id:
    )
  end

  def projection_event(
    payload,
    stream:,
    revision:,
    position:,
    policy_version: nil,
    actor_kind: "agent",
    actor_id: "agent-a",
    metadata: nil,
    causation_id: nil
  )
    ProjectionEventFactory.build(
      payload:,
      stream:,
      stream_revision: revision,
      global_position: position,
      policy_version:,
      actor_kind:,
      actor_id:,
      metadata:,
      command_id: "cmd-merge-snapshot-projection",
      correlation_id:,
      causation_id:
    )
  end

  def metadata_attributes(policy_version, actor_kind:, actor_id:)
    {
      command_id: "cmd-merge-snapshot-projection",
      actor_kind:,
      actor_id:,
      recorded_by: "coordinator",
      policy_version:
    }
  end

  def source_reference(type, stream_name, stream_id, revision)
    Coordinator::Write::EventReference.new(
      event_id: SecureRandom.uuid_v7,
      type:,
      stream_context: "DevelopmentIntegration",
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

  def constant_loader(value)
    Class.new do
      def initialize(value)
        @value = value
      end

      def call(_event, registration:)
        @value
      end
    end.new(value)
  end

  def digest(character)
    "sha256:#{character * 64}"
  end
end
