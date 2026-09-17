# frozen_string_literal: true

RSpec.describe "history migration merge transformers", :event_store do
  let(:source_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:target_store) do
    Coordinator::Write::EventStore.new(client: PgEventstore.client(:migration_target))
  end
  let(:registry) { Coordinator::Container["history_migrations.transformer_registry"] }
  let(:planner) { Coordinator::Container["history_migrations.event_planning_dispatcher"] }
  let(:dispatcher) { Coordinator::Container["history_migrations.event_dispatcher"] }
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:legacy_repository_id) { SecureRandom.uuid_v7 }
  let(:legacy_change_set_id) { "legacy-merge-change-set" }
  let(:legacy_work_item_id) { "legacy-merge-work-item" }
  let(:legacy_attempt_id) { "legacy-merge-attempt" }
  let(:legacy_candidate_id) { "legacy-merge-candidate" }
  let(:legacy_snapshot_id) { "legacy-merge-snapshot" }
  let(:legacy_verification_id) { SecureRandom.uuid_v7 }
  let(:legacy_authorization_id) { SecureRandom.uuid_v7 }
  let(:intention_set_id) { SecureRandom.uuid_v7 }
  let(:base_commit_oid) { "a" * 40 }
  let(:head_commit_oid) { "b" * 40 }
  let(:merge_commit_oid) { "c" * 40 }
  let(:manifest_digest) { "sha256:#{'1' * 64}" }
  let(:snapshot_digest) { "sha256:#{'2' * 64}" }
  let(:verification_input_digest) { "sha256:#{'3' * 64}" }
  let(:verification_digest) { "sha256:#{'4' * 64}" }
  let(:decision_digest) { "sha256:#{'5' * 64}" }
  let(:authorization_input_digest) { "sha256:#{'6' * 64}" }
  let(:observation_digest) { "sha256:#{'7' * 64}" }
  let(:source_correlation_id) { SecureRandom.uuid_v7 }

  before { persist_scope_roots }

  it "maps the complete legacy merge chronology into cohesive UUIDv7 target facts" do
    submitted = persist_payload(candidate_stream, candidate_payload)
    manifest = persist_payload(candidate_stream, manifest_payload)
    registration = persist_payload(
      snapshot_stream,
      snapshot_payload(submitted:, manifest:),
      markers: [ "merge-snapshot:#{legacy_snapshot_id}", "repository:#{legacy_repository_id}" ]
    )
    state = source_snapshot_state(registration:, submitted:, manifest:)
    commit = persist_payload(
      stream("DevelopmentIntegration", "MergeSnapshotCommit", "sha256:#{'8' * 64}"),
      commit_payload(registration),
      markers: [ "merge-snapshot:#{legacy_snapshot_id}", "repository:#{legacy_repository_id}" ]
    )
    submission = persist_payload(
      verification_stream,
      verification_submission_payload(registration:, state:),
      markers: [
        "merge-snapshot:#{legacy_snapshot_id}",
        "merge-snapshot-verification:#{legacy_verification_id}"
      ]
    )
    verified = persist_payload(
      snapshot_stream,
      verified_payload(registration:, state:, submission:),
      markers: [
        "merge-snapshot:#{legacy_snapshot_id}",
        "merge-snapshot-verification:#{legacy_verification_id}",
        "merge-snapshot-status:verified"
      ]
    )
    binding = snapshot_binding(registration:, verified:)
    authorization = persist_payload(
      authorization_stream,
      authorization_payload(registration:, state:, binding:),
      markers: [
        "merge-authorization:#{legacy_authorization_id}",
        "merge-snapshot:#{legacy_snapshot_id}"
      ]
    )
    observation = persist_payload(
      snapshot_stream,
      observation_payload(binding:, authorization:),
      markers: [ "merge-snapshot:#{legacy_snapshot_id}" ]
    )
    sources = [ submitted, manifest, registration, commit, submission, verified, authorization, observation ]
    upper_position = observation.global_position

    sources.each { expect(plan(_1, upper_position:)).to be_success }

    registration_facts = transform(registration, upper_position:).value!
    commit_fact = transform(commit, upper_position:).value!.sole
    submission_facts = transform(submission, upper_position:).value!
    verified_facts = transform(verified, upper_position:).value!
    authorization_fact = transform(authorization, upper_position:).value!.sole
    observation_facts = transform(observation, upper_position:).value!

    expect(registration_facts.map { _1.event.class }).to contain_exactly(
      Coordinator::Write::Events::MergeSnapshotRegisteredV2
    )
    expect(commit_fact.event).to be_a(Coordinator::Write::Events::MergeSnapshotCommitRegisteredV2)
    expect(submission_facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::MergeSnapshotVerificationSubmittedV2,
      Coordinator::Write::Events::MergeSnapshotVerificationAssignedV1
    ])
    expect(verified_facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::MergeSnapshotVerificationSelectedV1,
      Coordinator::Write::Events::MergeSnapshotVerifiedV2
    ])
    expect(authorization_fact.event).to be_a(Coordinator::Write::Events::MergeAuthorizationGrantedV2)
    expect(observation_facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::MergeObservedV2,
      Coordinator::Write::Events::MergeObservationAuthorizationLinkedV1
    ])

    transformed = registration_facts + [ commit_fact ] + submission_facts + verified_facts +
      [ authorization_fact ] + observation_facts
    expect(transformed.map { _1.target_stream.stream_id }.uniq).to all(
      match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    )
    expect(commit_fact.event.registry_id).to eq(commit_fact.target_stream.stream_id)
    expect(commit_fact.event.registry_id).not_to eq(commit.data.fetch("registry_id"))
    expect(transformed.flat_map(&:markers).join("\n")).not_to include("sha256:")
    expect(transformed.flat_map { _1.event.to_h.keys }).not_to include(
      :registered_at,
      :submitted_at,
      :verified_at,
      :decided_at,
      :recorded_at
    )
    expect(registration_facts.sole.metadata_extension).to have_attributes(
      snapshot_digest:,
      policy_version: "merge-snapshot-registration/v1"
    )
    expect(submission_facts.first.metadata_extension).to have_attributes(
      verification_input_digest:,
      policy_version: "merge-snapshot-verification/v1"
    )
    expect(verified_facts.last.metadata_extension.verification_digest).to eq(verification_digest)
    expect(authorization_fact.metadata_extension).to have_attributes(
      decision_digest:,
      input_digest: authorization_input_digest,
      policy_version: "merge-authorization/v1"
    )
    expect(observation_facts.first.metadata_extension).to have_attributes(
      authorization_decision_digest: decision_digest,
      observation_digest:,
      policy_version: "merge-observation/v1"
    )

    results = sources.map { dispatch(_1, upper_position:) }
    expect(results).to all(be_success)
    expect(sources.map { dispatch(_1, upper_position:).value!.outcome }.uniq).to eq([ "existing" ])

    target_registration = results.fetch(2).value!.events.sole
    target_snapshot_id = target_registration.data.fetch("merge_snapshot_id")
    snapshot = Coordinator::Write::MergeSnapshots::StateLoader.new(event_store: target_store).call(
      target_snapshot_id
    )
    verification = Coordinator::Write::MergeSnapshotVerifications::HistoryLoader.new(
      event_store: target_store
    ).call(target_snapshot_id)
    expect(snapshot).to have_attributes(
      merge_snapshot_id: target_snapshot_id,
      repository_id: match(Coordinator::Shared::Types::UUID_V7_PATTERN),
      snapshot_digest:
    )
    expect(snapshot.ordered_candidates.sole.candidate_id).to match(
      Coordinator::Shared::Types::UUID_V7_PATTERN
    )
    expect(verification.submissions.sole).to have_attributes(
      verification_input_digest:,
      policy_version: "merge-snapshot-verification/v1"
    )
    expect(verification.verified).to have_attributes(
      verification_digest:,
      policy_version: "merge-snapshot-verification/v1"
    )

    target_snapshot_events = target_store.read(
      stream("DevelopmentIntegration", "MergeSnapshot", target_snapshot_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[
          MergeSnapshotRegistered MergeSnapshotVerificationAssigned
          MergeSnapshotVerificationSelected MergeSnapshotVerified
          MergeObserved MergeObservationAuthorizationLinked
        ],
        maximum_count: 6,
        direction: :asc
      )
    )
    expect(target_snapshot_events.map(&:type)).to eq(%w[
      MergeSnapshotRegistered MergeSnapshotVerificationAssigned
      MergeSnapshotVerificationSelected MergeSnapshotVerified
      MergeObserved MergeObservationAuthorizationLinked
    ])
    expect(target_snapshot_events.map(&:correlation_id).uniq).to contain_exactly(
      target_snapshot_events.first.correlation_id
    )
    expect(target_snapshot_events.fetch(4).metadata).to include(
      "authorization_decision_digest" => decision_digest,
      "observation_digest" => observation_digest
    )
  end

  it "fails closed when a verification points at a different snapshot registration" do
    submitted = persist_payload(candidate_stream, candidate_payload)
    manifest = persist_payload(candidate_stream, manifest_payload)
    registration = persist_payload(
      snapshot_stream,
      snapshot_payload(submitted:, manifest:),
      markers: [ "merge-snapshot:#{legacy_snapshot_id}" ]
    )
    state = source_snapshot_state(registration:, submitted:, manifest:)
    wrong_reference = event_reference(registration).to_h.merge(event_id: SecureRandom.uuid_v7)
    original = verification_submission_payload(registration:, state:)
    invalid = original.class.new(
      original.to_h.merge(
        snapshot: Coordinator::Write::MergeSnapshotVerifications::SnapshotEvidenceV1.new(
          snapshot: state,
          event: Coordinator::Write::EventReference.new(wrong_reference)
        )
      )
    )
    source_event = persist_payload(
      verification_stream,
      invalid,
      markers: [ "merge-snapshot:#{legacy_snapshot_id}" ]
    )

    result = transform(source_event, upper_position: source_event.global_position)

    expect(result).to be_failure
    expect(result.failure).to have_attributes(
      code: :ambiguous_source_reference,
      event_type: "MergeSnapshotVerificationSubmitted",
      schema_version: 1,
      source_event_id: source_event.id
    )
  end

  private

  def persist_scope_roots
    persist_raw(stream("DevelopmentPlanning", "Repository", legacy_repository_id), type: "RepositoryRegistered")
    persist_raw(stream("DevelopmentPlanning", "ChangeSet", legacy_change_set_id), type: "ChangeSetCreated")
    persist_raw(stream("DevelopmentExecution", "WorkItem", legacy_work_item_id), type: "WorkItemCreated")
    persist_raw(stream("DevelopmentExecution", "Attempt", legacy_attempt_id), type: "AttemptAuthorized")
  end

  def candidate_payload
    Coordinator::Write::Events::CandidateSubmittedV2.new(
      candidate_id: legacy_candidate_id,
      change_set_id: legacy_change_set_id,
      work_item_id: legacy_work_item_id,
      attempt_id: legacy_attempt_id,
      agent_id: "legacy-agent",
      repository_id: legacy_repository_id,
      target_branch: "main",
      object_format: "sha1",
      base_commit_oid:,
      head_commit_oid:,
      checkpoint_kind: "final",
      lease_set_id: intention_set_id,
      lease_policy_version: Coordinator::Write::LeaseResourceV2::POLICY_VERSION,
      lease_references: [
        Coordinator::Write::LeaseReferenceV2.new(
          lease_id: SecureRandom.uuid_v7,
          resource_id: SecureRandom.uuid_v7,
          resource_kind: "file",
          resource_path: "lib/merge_candidate.rb",
          base_blob_oid: base_commit_oid,
          fencing_token: 1
        )
      ],
      manifest_digest:,
      build_context_digest: nil,
      evidence_status: "attributed_unverified",
      submitted_at: "2026-08-01T10:00:00.000001Z"
    )
  end

  def manifest_payload
    Coordinator::Write::Events::CandidateChangeManifestCapturedV1.new(
      candidate_id: legacy_candidate_id,
      repository_id: legacy_repository_id,
      target_branch: "main",
      object_format: "sha1",
      base_commit_oid:,
      head_commit_oid:,
      evidence_revision: 1,
      policy_version: Coordinator::Write::Candidates::ChangeManifestDocumentV1::SCHEMA,
      manifest_digest:,
      files: [
        Coordinator::Write::Candidates::ManifestFileV1.new(
          status: "modified",
          old_path: "lib/merge_candidate.rb",
          new_path: "lib/merge_candidate.rb",
          old_blob_oid: base_commit_oid,
          new_blob_oid: head_commit_oid,
          old_mode: "100644",
          new_mode: "100644"
        )
      ],
      collector: Coordinator::Write::Candidates::EvidenceCollectorV1.new(
        kind: "agent",
        id: "legacy-agent",
        collector_version: "git-diff-tree/v1"
      ),
      captured_at: "2026-08-01T10:01:00.000001Z"
    )
  end

  def snapshot_payload(submitted:, manifest:)
    Coordinator::Write::Events::MergeSnapshotRegisteredV1.new(
      merge_snapshot_id: legacy_snapshot_id,
      repository_id: legacy_repository_id,
      target_branch: "main",
      object_format: "sha1",
      target_base_commit_oid: base_commit_oid,
      ordered_candidates: [ candidate_member(submitted:, manifest:) ],
      merge_commit_oid:,
      producer: Coordinator::Write::MergeSnapshots::ProducerV1.new(
        name: "git-merge",
        version: "2.47.0"
      ),
      run_id: "legacy-merge-run",
      produced_at: "2026-08-01T10:02:00.000001Z",
      snapshot_digest:,
      policy_version: "merge-snapshot-registration/v1",
      evidence_status: "attributed_unverified",
      registered_at: "2026-08-01T10:02:01.000001Z"
    )
  end

  def candidate_member(submitted:, manifest:)
    Coordinator::Write::MergeSnapshots::CandidateMemberV1.new(
      candidate_id: legacy_candidate_id,
      change_set_id: legacy_change_set_id,
      work_item_id: legacy_work_item_id,
      attempt_id: legacy_attempt_id,
      repository_id: legacy_repository_id,
      target_branch: "main",
      object_format: "sha1",
      base_commit_oid:,
      head_commit_oid:,
      manifest_digest:,
      candidate_event: event_reference(submitted),
      manifest_event: event_reference(manifest)
    )
  end

  def source_snapshot_state(registration:, submitted:, manifest:)
    Coordinator::Write::MergeSnapshots::StateV2.new(
      merge_snapshot_id: legacy_snapshot_id,
      repository_id: legacy_repository_id,
      target_branch: "main",
      object_format: "sha1",
      target_base_commit_oid: base_commit_oid,
      merge_commit_oid:,
      ordered_candidates: [ candidate_member(submitted:, manifest:) ],
      producer: "git-merge",
      run_id: "legacy-merge-run",
      produced_at: "2026-08-01T10:02:00.000001Z",
      snapshot_digest:,
      registration_event: event_reference(registration)
    )
  end

  def commit_payload(registration)
    Coordinator::Write::Events::MergeSnapshotCommitRegisteredV1.new(
      registry_id: "sha256:#{'8' * 64}",
      merge_snapshot_id: legacy_snapshot_id,
      repository_id: legacy_repository_id,
      object_format: "sha1",
      merge_commit_oid:,
      snapshot_event: event_reference(registration),
      registered_at: "2026-08-01T10:02:02.000001Z"
    )
  end

  def verification_submission_payload(registration:, state:)
    Coordinator::Write::Events::MergeSnapshotVerificationSubmittedV1.new(
      merge_snapshot_id: legacy_snapshot_id,
      snapshot: Coordinator::Write::MergeSnapshotVerifications::SnapshotEvidenceV1.new(
        snapshot: state,
        event: event_reference(registration)
      ),
      verification_id: legacy_verification_id,
      policy_version: "merge-snapshot-verification/v1",
      assessment: verification_assessment,
      verification_input_digest:,
      submitted_at: "2026-08-01T10:03:00.000001Z"
    )
  end

  def verification_assessment
    Coordinator::Write::MergeSnapshotVerifications::AssessmentV1.new(
      evidence_kind: "combined_tests",
      producer: Coordinator::Write::MergeSnapshotVerifications::ProducerV1.new(
        name: "rspec",
        version: "3.13.0"
      ),
      run_id: "legacy-verification-run",
      test_suite_digest: "sha256:#{'9' * 64}",
      environment_digest: "sha256:#{'a' * 64}",
      result_digest: "sha256:#{'b' * 64}",
      conclusion: "passed",
      findings: [],
      produced_at: "2026-08-01T10:03:00.000001Z"
    )
  end

  def verified_payload(registration:, state:, submission:)
    Coordinator::Write::Events::MergeSnapshotVerifiedV1.new(
      merge_snapshot_id: legacy_snapshot_id,
      snapshot: Coordinator::Write::MergeSnapshotVerifications::SnapshotEvidenceV1.new(
        snapshot: state,
        event: event_reference(registration)
      ),
      policy_version: "merge-snapshot-verification/v1",
      selected_verification: Coordinator::Write::MergeSnapshotVerifications::VerificationDecisionReferenceV1.new(
        verification_id: legacy_verification_id,
        evidence_kind: "combined_tests",
        conclusion: "passed",
        result_digest: "sha256:#{'b' * 64}",
        verification_input_digest:,
        event: event_reference(submission)
      ),
      verification_digest:,
      verified_at: "2026-08-01T10:04:00.000001Z"
    )
  end

  def snapshot_binding(registration:, verified:)
    Coordinator::Write::MergeAuthorizations::SnapshotBindingV1.new(
      registration_event: event_reference(registration),
      snapshot_digest:,
      verification_event: event_reference(verified),
      verification_digest:
    )
  end

  def authorization_payload(registration:, state:, binding:)
    Coordinator::Write::Events::MergeAuthorizationGrantedV1.new(
      authorization_id: legacy_authorization_id,
      merge_snapshot_id: legacy_snapshot_id,
      policy_version: "merge-authorization/v1",
      snapshot_binding: binding,
      expected_impact_policy: nil,
      evaluation: authorization_evaluation(registration:, state:),
      input_digest: authorization_input_digest,
      decision_digest:,
      decided_at: "2026-08-01T10:05:00.000001Z"
    )
  end

  def authorization_evaluation(registration:, state:)
    Coordinator::Write::MergeAuthorizations::EvaluationV1.new(
      merge_snapshot_id: legacy_snapshot_id,
      snapshot: Coordinator::Write::MergeAuthorizations::SnapshotEvidenceV1.new(
        registration: state,
        registration_event: event_reference(registration),
        verification: nil,
        verification_event: nil
      ),
      target_base_observation: Coordinator::Write::MergeAuthorizations::TargetBaseObservationV1.new(
        repository_id: legacy_repository_id,
        target_branch: "main",
        object_format: "sha1",
        commit_oid: base_commit_oid,
        observer: Coordinator::Write::MergeSnapshotVerifications::ProducerV1.new(
          name: "git-fetch",
          version: "2.47.0"
        ),
        run_id: "legacy-target-base-run",
        observed_at: "2026-08-01T10:04:30.000001Z"
      ),
      current_policy: nil,
      candidates: [],
      work_item_progress: [],
      obligations: [],
      reasons: []
    )
  end

  def observation_payload(binding:, authorization:)
    Coordinator::Write::Events::MergeObservedV1.new(
      merge_snapshot_id: legacy_snapshot_id,
      authorization_event: event_reference(authorization),
      authorization_decision_digest: decision_digest,
      snapshot_binding: binding,
      repository_id: legacy_repository_id,
      target_branch: "main",
      object_format: "sha1",
      target_before_commit_oid: base_commit_oid,
      target_after_commit_oid: merge_commit_oid,
      observer: Coordinator::Write::MergeObservations::ObserverV1.new(
        name: "git-provider-webhook",
        version: "2026-08"
      ),
      run_id: "legacy-observation-run",
      observed_at: "2026-08-01T10:06:00.000001Z",
      observation_digest:,
      policy_version: "merge-observation/v1",
      evidence_status: "attributed_unverified",
      recorded_at: "2026-08-01T10:06:01.000001Z"
    )
  end

  def transform(source_event, upper_position:)
    registry.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event:
    )
  end

  def plan(source_event, upper_position:)
    planner.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event:
    )
  end

  def dispatch(source_event, upper_position:)
    HistoryMigrationWaveDispatch.call(
      dispatcher:,
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event:
    )
  end

  def persist_payload(target_stream, payload, markers: [])
    persist_raw(
      target_stream,
      type: payload.class.event_type,
      data: payload.to_h,
      schema_version: payload.class.schema_version,
      markers:
    )
  end

  def persist_raw(target_stream, type:, data: {}, schema_version: 1, markers: [])
    source_store.append(
      target_stream,
      [
        PgEventstore::Event.new(
          id: SecureRandom.uuid_v7,
          type:,
          data:,
          metadata: {
            "schema_version" => schema_version,
            "command_id" => SecureRandom.uuid_v7,
            "actor_kind" => "agent",
            "actor_id" => "legacy-agent",
            "recorded_by" => "coordinator",
            "policy_version" => "legacy-policy/v1"
          },
          markers:,
          correlation_id: source_correlation_id
        )
      ]
    ).sole
  end

  def candidate_stream
    stream("DevelopmentIntegration", "Candidate", legacy_candidate_id)
  end

  def snapshot_stream
    stream("DevelopmentIntegration", "MergeSnapshot", legacy_snapshot_id)
  end

  def verification_stream
    stream("DevelopmentIntegration", "MergeVerification", legacy_verification_id)
  end

  def authorization_stream
    stream("DevelopmentIntegration", "MergeAuthorization", legacy_authorization_id)
  end

  def stream(context, stream_name, stream_id)
    Coordinator::Write::StreamReference.new(context:, stream_name:, stream_id:)
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
end
