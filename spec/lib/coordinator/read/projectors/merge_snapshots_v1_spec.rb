# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::MergeSnapshotsV1, :read_model, :event_store do
  subject(:projector) { described_class.new(registration_loader:) }

  let(:repository) { Coordinator::Read::Repositories::MergeSnapshots.new }
  let(:merge_snapshot_id) { "MS-merge-projection" }
  let(:repository_id) { "018f0f4d-4e45-7abc-8def-000000000401" }
  let(:candidate_id) { "CAN-merge-projection" }
  let(:verification_id) { "018f0f4d-4e45-7abc-8def-000000000402" }
  let(:correlation_id) { SecureRandom.uuid_v7 }
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:registration_loader) { Coordinator::Read::MergeSnapshots::RegistrationLoader.new(event_store:) }

  it "serves an available not-found view during lag and converges idempotently" do
    query = Coordinator::Read::Queries::MergeSnapshotGet.new
    expect(query.call(merge_snapshot_id:).value!.status).to eq("not_found")

    projector.call([ registration_event ])
    projector.call([ registration_event ])

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
    create(:coordinator_read_merge_snapshot, merge_snapshot_id:, repository_id:)
    projector.call([ verification_submission_event ])
    projector.call([ verification_assignment_event ])

    observed = repository.fetch(merge_snapshot_id)
    expect(observed.verification).to have_attributes(status: "unverified")
    expect(observed.verification.submissions.sole.assessment.conclusion).to eq("passed")

    projector.call([ verification_selection_event ])
    expect(repository.fetch(merge_snapshot_id).verification.verified).to be_nil

    projector.call([ verified_event ])
    projector.call([ verified_event ])
    converged = repository.fetch(merge_snapshot_id)
    expect(converged.verification).to have_attributes(status: "verified")
    expect(converged.verification.verified.selected_verification.verification_id).to eq(verification_id)
    expect(converged.verification.verified.verification_digest).to eq(digest("7"))
  end

  it "serves the latest exact authorization without imposing a freshness gate" do
    project_verified_snapshot
    expect(repository.fetch(merge_snapshot_id).latest_authorization).to be_nil

    granted = authorization_event(outcome: "granted", position: 400)
    projector.call([ granted ])
    projector.call([ granted ])
    expect(repository.fetch(merge_snapshot_id).latest_authorization).to have_attributes(
      authorization_id: granted.stream.stream_id,
      outcome: "granted",
      decision_digest: digest("9")
    )

    denied = authorization_event(outcome: "denied", position: 500)
    projector.call([ denied ])
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
    projector.call([ authorization ])

    observed, linked = observation_events(authorization)
    projector.call([ observed ])
    expect(repository.fetch(merge_snapshot_id).observation).to be_nil

    projector.call([ linked ])
    projector.call([ linked ])
    observation = repository.fetch(merge_snapshot_id).observation
    expect(observation).to have_attributes(
      target_after_commit_oid: "9" * 40,
      observer: "git-observer",
      evidence_status: "attributed_unverified",
      authorization_event: event_reference(authorization)
    )
  end

  it "reapplies registration columns without resetting verification or observation" do
    record = create(:coordinator_read_merge_snapshot, merge_snapshot_id:, repository_id:,
      verification_status: "verified", verified_decision: { note: "retained" }, observation: { note: "retained" })
    original = record.attributes.slice("verification_status", "verified_decision", "observation")

    projector.call([ registration_event ])

    expect(record.reload.attributes.slice(*original.keys)).to eq(original)
    expect(record.snapshot_digest).to eq(digest("2"))
    expect(Coordinator::Read::ProcessedProjectionEvent.count).to eq(0)
  end

  it "keeps verification entries and completed selection stable under whole-chunk and individual redelivery" do
    create(:coordinator_read_merge_snapshot, merge_snapshot_id:, repository_id:)
    events = [ verification_submission_event, verification_assignment_event, verification_selection_event, verified_event ]
    2.times { projector.call(events) }
    record = Coordinator::Read::MergeSnapshot.find(merge_snapshot_id)
    original = record.verified_decision
    projector.call([ verification_selection_event ])

    expect(record.reload.verification_submissions.length).to eq(1)
    expect(record.verified_decision).to eq(original)
    expect(repository.fetch(merge_snapshot_id).verification.status).to eq("verified")
    expect(Coordinator::Read::ProcessedProjectionEvent.count).to eq(0)
  end

  it "preserves the assigned authorization when the original observation is redelivered" do
    project_verified_snapshot
    authorization = authorization_event(outcome: "granted", position: 400)
    observed, linked = observation_events(authorization)
    projector.call([ authorization, observed, linked ])
    original = Coordinator::Read::MergeSnapshot.find(merge_snapshot_id).observation

    projector.call([ observed ])

    expect(Coordinator::Read::MergeSnapshot.find(merge_snapshot_id).observation).to eq(original)
  end

  it "updates a thousand assignment timestamps without loading unrelated collections" do
    rows = Array.new(1000) do |index|
      attributes_for(:coordinator_read_merge_snapshot, merge_snapshot_id: "MS-batch-#{index}", repository_id:,
        merge_commit_oid: (index + 1).to_s(16).rjust(40, "0"), updated_at: Time.utc(2026, 8, 29))
    end
    Coordinator::Read::MergeSnapshot.insert_all!(rows)
    events = rows.map.with_index do |row, index|
      ProjectionEventFactory.build(
        payload: Coordinator::Write::Events::MergeSnapshotVerificationAssignedV1.new(
          merge_snapshot_id: row.fetch(:merge_snapshot_id), verification_id:),
        stream: Coordinator::Write::StreamFactory.new.merge_snapshot(row.fetch(:merge_snapshot_id)),
        stream_revision: 1, global_position: index + 2000, policy_version: "merge-snapshot-verification/v1")
    end
    statements = []
    ActiveSupport::Notifications.subscribed(->(*args) { statements << args.last.fetch(:sql) }, "sql.active_record") do
      projector.call(events)
    end

    expect(statements.count { _1.start_with?("UPDATE") }).to eq(1)
    expect(statements.count { _1.start_with?("SELECT") && _1.include?('FROM "merge_snapshots"') }).to eq(0)
    expect(Coordinator::Read::MergeSnapshot.where(updated_at: events.first.created_at).count).to eq(1000)
    expect(Coordinator::Read::ProcessedProjectionEvent.count).to eq(0)
  end

  def project_verified_snapshot
    create(:coordinator_read_merge_snapshot, merge_snapshot_id:, repository_id:)
    [
      verification_submission_event,
      verification_assignment_event,
      verification_selection_event,
      verified_event
    ].each { projector.call([ _1 ]) }
  end

  def registration_event
    persist_candidate_member
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

  def persist_candidate_member
    return @candidate_member_events if @candidate_member_events

    payloads = [
      Coordinator::Write::Events::CandidateCreatedV1.new(candidate_id:),
      Coordinator::Write::Events::CandidateAssignedToAttemptV1.new(candidate_id:, change_set_id: "CS-merge-projection",
        work_item_id: "WI-merge-projection", attempt_id: "ATT-merge-projection"),
      Coordinator::Write::Events::CandidateAssignedToRepositoryV1.new(candidate_id:, repository_id:),
      Coordinator::Write::Events::CandidateTargetBranchSelectedV1.new(candidate_id:, target_branch: "main"),
      Coordinator::Write::Events::CandidateCommitRangeDeclaredV1.new(candidate_id:, object_format: "sha1", base_commit_oid: "a" * 40, head_commit_oid: "b" * 40),
      Coordinator::Write::Events::CandidateCheckpointKindSelectedV1.new(candidate_id:, checkpoint_kind: "final"),
      Coordinator::Write::Events::CandidateWorkIntentionSetAssignedV1.new(candidate_id:, intention_set_id: SecureRandom.uuid_v7),
      Coordinator::Write::Events::CandidateChangeManifestCapturedV2.new(candidate_id:, evidence_revision: 1,
        files: [ Coordinator::Write::Candidates::ManifestFileV1.new(status: "modified", old_path: "lib/merge.rb", new_path: "lib/merge.rb",
          old_blob_oid: "c" * 40, new_blob_oid: "d" * 40, old_mode: "100644", new_mode: "100644") ]),
      Coordinator::Write::Events::CandidateSubmittedV3.new(candidate_id:)
    ]
    events = payloads.map do |payload|
      attributes = metadata_attributes("candidate-submission/v3", actor_kind: "agent", actor_id: "agent-a")
      metadata = if payload.class.event_type == "CandidateChangeManifestCaptured"
        Coordinator::Write::Metadata::CandidateChangeManifestV2.new(**attributes,
          policy_version: "candidate-change-manifest/v1", manifest_digest: digest("1"),
          collector: { kind: "agent", id: "agent-a", collector_version: "git-evidence-v1" })
      else
        Coordinator::Write::EventMetadata.new(**attributes)
      end
      Coordinator::Write::EventFactory.new.build!(event: payload, metadata:, event_id: SecureRandom.uuid_v7,
        markers: [ "candidate:#{candidate_id}" ], correlation_id:)
    end
    @candidate_member_events = event_store.append(Coordinator::Write::StreamFactory.new.candidate(candidate_id), events)
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

  def digest(character)
    "sha256:#{character * 64}"
  end
end
