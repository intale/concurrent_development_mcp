# frozen_string_literal: true

RSpec.describe "history migration ReleaseSet transformers", :event_store do
  let(:source_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:target_store) do
    Coordinator::Write::EventStore.new(client: PgEventstore.client(:migration_target))
  end
  let(:registry) { Coordinator::Container["history_migrations.transformer_registry"] }
  let(:planner) { Coordinator::Container["history_migrations.event_planning_dispatcher"] }
  let(:dispatcher) { Coordinator::Container["history_migrations.event_dispatcher"] }
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:source_correlation_id) { SecureRandom.uuid_v7 }
  let(:legacy_change_set_id) { "legacy-release-change-set" }
  let(:legacy_release_set_id) { "sha256:#{'0' * 64}" }

  before { persist_scope_roots }

  it "migrates an activated ReleaseSet into cohesive current facts" do
    members = build_members
    prepared = persist_preparation(members)
    integrations = members.map.with_index do |member, index|
      persist_integration(prepared, member, index:, outcome: "integrated")
    end
    verification = persist_verification(prepared, integrations, outcome: "passed")
    activation = persist_activation(prepared, verification)
    completed = persist_completion(prepared, outcome: "activated", source_event: activation)
    release_events = [ prepared, *integrations, verification, activation, completed ]
    upper_position = completed.global_position

    plan_and_dispatch_dependencies(members, upper_position:)
    release_events.each { expect(plan(_1, upper_position:)).to be_success }

    preparation_facts = transform(prepared, upper_position:).value!
    integration_facts = integrations.flat_map { transform(_1, upper_position:).value! }
    verification_facts = transform(verification, upper_position:).value!
    activation_fact = transform(activation, upper_position:).value!.sole
    completion_facts = transform(completed, upper_position:).value!

    expect(preparation_facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::ReleaseSetCreatedV1,
      Coordinator::Write::Events::ReleaseSetMemberAddedV1,
      Coordinator::Write::Events::ReleaseSetMemberAddedV1,
      Coordinator::Write::Events::ReleaseSetPreparedV2
    ])
    target_release_set_id = preparation_facts.first.target_stream.stream_id
    expect(target_release_set_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(target_release_set_id).not_to eq(legacy_release_set_id)
    expect(preparation_facts.fetch(1).event.ordered_candidate_ids).to all(
      match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    )
    expect(preparation_facts.last.metadata_extension).to have_attributes(
      release_digest: event_payload(prepared).release_digest,
      policy_version: "release-set-preparation/v1"
    )
    expect(integration_facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::RepositoryIntegrationRecordedV2,
      Coordinator::Write::Events::RepositoryIntegrationMergeLinkedV1,
      Coordinator::Write::Events::RepositoryIntegrationRecordedV2,
      Coordinator::Write::Events::RepositoryIntegrationMergeLinkedV1
    ])
    expect(verification_facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::ReleaseSetVerificationRecordedV2,
      Coordinator::Write::Events::ReleaseSetIntegrationLinkedV1,
      Coordinator::Write::Events::ReleaseSetIntegrationLinkedV1
    ])
    expect(activation_fact.event).to be_a(Coordinator::Write::Events::ReleaseSetActivatedV2)
    expect(activation_fact.event.activation_point.to_h).not_to have_key(:activated_at)
    expect(completion_facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::ReleaseSetOutcomeRecordedV1,
      Coordinator::Write::Events::ReleaseSetCompletedV2
    ])

    transformed = preparation_facts + integration_facts + verification_facts +
      [ activation_fact ] + completion_facts
    expect(transformed.flat_map(&:markers).join("\n")).not_to include("sha256:")
    expect(transformed.flat_map { _1.event.to_h.keys }).not_to include(
      :prepared_at, :recorded_at, :completed_at
    )

    release_events.each { expect(dispatch(_1, upper_position:)).to be_success }
    expect(release_events.map { dispatch(_1, upper_position:).value!.outcome }.uniq).to eq([ "existing" ])

    state = Coordinator::Write::ReleaseSets::HistoryLoader.new(event_store: target_store).call(
      target_release_set_id
    )
    expect(state.preparation.payload).to have_attributes(
      release_set_id: target_release_set_id,
      change_set_id: match(Coordinator::Shared::Types::UUID_V7_PATTERN),
      ordered_members: have_attributes(length: 2)
    )
    expect(state.integrations.map(&:merge_observation)).to all(be_a(Coordinator::Write::EventReference))
    expect(state.verifications.sole.integration_events).to eq(state.successful_integrations.map(&:event))
    expect(state.completion.payload.outcome).to eq("activated")
    expect(state.completed?).to be(true)

    persisted = read_target(preparation_facts.first.target_stream)
    expect(persisted.map(&:stream_revision)).to eq((0...persisted.length).to_a)
    expect(persisted.map(&:correlation_id).uniq).to contain_exactly(persisted.first.correlation_id)
    expect(persisted.find { _1.type == "ReleaseSetPrepared" }.metadata).to include(
      "release_digest" => event_payload(prepared).release_digest
    )
    expect(persisted.find { _1.type == "ReleaseSetActivated" }.metadata).to include(
      "activation_digest" => event_payload(activation).activation_digest
    )
  end

  it "splits compensated completion evidence into ordered repository facts" do
    members = build_members
    prepared = persist_preparation(members)
    successful = persist_integration(prepared, members.fetch(0), index: 0, outcome: "integrated")
    failed = persist_integration(prepared, members.fetch(1), index: 1, outcome: "failed")
    request = persist_compensation_request(prepared, successful:, trigger: failed)
    completed = persist_completion(
      prepared,
      outcome: "compensated",
      source_event: request,
      successful_integrations: [ successful ]
    )
    release_events = [ prepared, successful, failed, request, completed ]
    upper_position = completed.global_position

    plan_and_dispatch_dependencies(members, upper_position:)
    release_events.each { expect(plan(_1, upper_position:)).to be_success }

    failed_fact = transform(failed, upper_position:).value!.sole
    request_facts = transform(request, upper_position:).value!
    completion_facts = transform(completed, upper_position:).value!
    target_release_set_id = transform(prepared, upper_position:).value!.first.target_stream.stream_id

    expect(failed_fact.event.failure).to have_attributes(
      code: "merge_conflict",
      summary: "Conflicting target branch",
      result_digest: digest("failed-integration")
    )
    expect(failed_fact.event.failure.to_h).not_to have_key(:occurred_at)
    expect(request_facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::ReleaseSetCompensationRequestedV2,
      Coordinator::Write::Events::ReleaseSetSuccessfulIntegrationLinkedV1
    ])
    expect(completion_facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::RepositoryCompensationRecordedV1,
      Coordinator::Write::Events::ReleaseSetOutcomeRecordedV1,
      Coordinator::Write::Events::ReleaseSetCompletedV2
    ])
    compensation = completion_facts.first
    expect(compensation.event).to have_attributes(
      repository_id: match(Coordinator::Shared::Types::UUID_V7_PATTERN),
      integration_event: request_facts.last.event.integration_event,
      action: "revert"
    )
    expect(compensation.metadata_extension).to have_attributes(
      result_digest: digest("compensation"),
      producer: have_attributes(name: "release-reverter", version: "1.0.0"),
      run_id: "legacy-compensation-run"
    )

    release_events.each { expect(dispatch(_1, upper_position:)).to be_success }
    state = Coordinator::Write::ReleaseSets::HistoryLoader.new(event_store: target_store).call(
      target_release_set_id
    )
    expect(state.compensation_request.successful_integrations).to eq(
      state.compensation_evidence.map(&:integration_event)
    )
    expect(state.compensation_evidence.sole).to have_attributes(
      result_digest: digest("compensation"),
      run_id: "legacy-compensation-run"
    )
    expect(state.completion.payload.outcome).to eq("compensated")
    expect(state.completed?).to be(true)
  end

  it "fails closed when a ReleaseSet member binds a different authorization" do
    members = build_members
    original = members.first.fetch(:member)
    members.first[:member] = original.new(
      authorization_decision_digest: digest("wrong-authorization")
    )
    prepared = persist_preparation(members)
    upper_position = prepared.global_position
    plan_merge_dependencies(members, upper_position:)

    result = transform(prepared, upper_position:)

    expect(result).to be_failure
    expect(result.failure).to have_attributes(
      code: :ambiguous_source_reference,
      event_type: "ReleaseSetPrepared",
      schema_version: 1,
      source_event_id: prepared.id
    )
  end

  private

  def build_members
    2.times.map { build_member(_1) }
  end

  def build_member(index)
    repository_id = repository_id(index)
    source_candidate = candidate_payload(index)
    HistoryMigrationCandidateFixture.persist_reservation(event_store: source_store, candidate: source_candidate)
    candidate = persist_payload(candidate_stream(index), source_candidate)
    manifest = persist_payload(candidate_stream(index), manifest_payload(index))
    registration = persist_payload(
      snapshot_stream(index),
      snapshot_payload(index, candidate:, manifest:),
      markers: [ "merge-snapshot:#{snapshot_id(index)}", "repository:#{repository_id}" ]
    )
    state = source_snapshot_state(index, registration:, candidate:, manifest:)
    submission = persist_payload(
      verification_stream(index),
      verification_submission_payload(index, registration:, state:),
      markers: [ "merge-snapshot:#{snapshot_id(index)}" ]
    )
    verified = persist_payload(
      snapshot_stream(index),
      verified_payload(index, registration:, state:, submission:),
      markers: [ "merge-snapshot:#{snapshot_id(index)}", "merge-snapshot-status:verified" ]
    )
    binding = snapshot_binding(index, registration:, verified:)
    authorization = persist_payload(
      authorization_stream(index),
      authorization_payload(index, registration:, state:, binding:),
      markers: [ "merge-authorization:#{authorization_id(index)}", "merge-snapshot:#{snapshot_id(index)}" ]
    )
    observation = persist_payload(
      snapshot_stream(index),
      observation_payload(index, binding:, authorization:),
      markers: [ "merge-snapshot:#{snapshot_id(index)}" ]
    )
    {
      candidate:,
      manifest:,
      registration:,
      submission:,
      verified:,
      authorization:,
      observation:,
      member: Coordinator::Write::ReleaseSets::MemberEvidenceV1.new(
        position: index + 1,
        repository_id:,
        target_branch: "main",
        object_format: "sha1",
        merge_snapshot_id: snapshot_id(index),
        change_set_id: legacy_change_set_id,
        target_base_commit_oid: base_oid(index),
        merge_commit_oid: merge_oid(index),
        snapshot_binding: binding,
        authorization_event: event_reference(authorization),
        authorization_decision_digest: decision_digest(index),
        ordered_candidates: [ candidate_member(index, candidate:, manifest:) ]
      )
    }
  end

  def persist_preparation(members)
    ordered_members = members.map { _1.fetch(:member) }
    policy_version = "release-set-preparation/v1"
    release_digest = legacy_release_digest_builder.call(
      :release,
      release_set_id: legacy_release_set_id,
      change_set_id: legacy_change_set_id,
      ordered_members:,
      policy_version:
    )
    persist_payload(
      release_stream,
      Coordinator::Write::Events::ReleaseSetPreparedV1.new(
        release_set_id: legacy_release_set_id,
        change_set_id: legacy_change_set_id,
        ordered_members:,
        release_digest:,
        policy_version:,
        prepared_at: "2026-08-01T11:00:00.000001Z"
      ),
      markers: [ "release-set:#{legacy_release_set_id}" ]
    )
  end

  def persist_integration(prepared, member, index:, outcome:)
    preparation = event_payload(prepared)
    source_member = member.fetch(:member)
    observation = member.fetch(:observation)
    policy_version = "release-set-integration/v1"
    attributes = {
      release_set_id: legacy_release_set_id,
      release_digest: preparation.release_digest,
      repository_id: source_member.repository_id,
      member_position: source_member.position,
      attempt_id: "legacy-release-attempt-#{index + 1}",
      attempt_number: 1,
      outcome:,
      merge_observation_event: outcome == "integrated" ? event_reference(observation) : nil,
      observation_digest: outcome == "integrated" ? observation_digest(index) : nil,
      failure: outcome == "failed" ? integration_failure : nil,
      policy_version:
    }
    integration_digest = legacy_release_digest_builder.call(:integration, **attributes)
    persist_payload(
      release_stream,
      Coordinator::Write::Events::RepositoryIntegrationRecordedV1.new(
        **attributes,
        change_set_id: legacy_change_set_id,
        integration_digest:,
        evidence_status: "attributed_unverified",
        recorded_at: "2026-08-01T11:0#{index + 1}:00.000001Z"
      ),
      markers: [ "release-set:#{legacy_release_set_id}" ]
    )
  end

  def persist_verification(prepared, integrations, outcome:)
    preparation = event_payload(prepared)
    integration_events = integrations.map { event_reference(_1) }
    evidence = verification_evidence(outcome)
    policy_version = "release-set-verification/v1"
    attributes = {
      release_set_id: legacy_release_set_id,
      release_digest: preparation.release_digest,
      attempt_number: 1,
      integration_events:,
      evidence:,
      policy_version:
    }
    verification_digest = legacy_release_digest_builder.call(:verification, **attributes)
    persist_payload(
      release_stream,
      Coordinator::Write::Events::ReleaseSetVerificationRecordedV1.new(
        **attributes,
        change_set_id: legacy_change_set_id,
        verification_digest:,
        evidence_status: "attributed_unverified",
        recorded_at: "2026-08-01T11:03:00.000001Z"
      ),
      markers: [ "release-set:#{legacy_release_set_id}" ]
    )
  end

  def persist_activation(prepared, verification)
    preparation = event_payload(prepared)
    verification_payload = event_payload(verification)
    activation_point = Coordinator::Write::ReleaseSets::ActivationPointV1.new(
      kind: "deployment_manifest",
      environment: "production",
      external_reference: "deployments/legacy-release",
      state_digest: digest("activation-state"),
      producer: evidence_producer("release-deployer"),
      run_id: "legacy-activation-run",
      activated_at: "2026-08-01T11:04:00.000001Z"
    )
    policy_version = "release-set-activation/v1"
    attributes = {
      release_set_id: legacy_release_set_id,
      release_digest: preparation.release_digest,
      verification_event: event_reference(verification),
      verification_digest: verification_payload.verification_digest,
      activation_point:,
      policy_version:
    }
    activation_digest = legacy_release_digest_builder.call(:activation, **attributes)
    persist_payload(
      release_stream,
      Coordinator::Write::Events::ReleaseSetActivatedV1.new(
        **attributes,
        change_set_id: legacy_change_set_id,
        activation_digest:,
        evidence_status: "attributed_unverified",
        recorded_at: "2026-08-01T11:04:01.000001Z"
      ),
      markers: [ "release-set:#{legacy_release_set_id}" ]
    )
  end

  def persist_compensation_request(prepared, successful:, trigger:)
    preparation = event_payload(prepared)
    persist_payload(
      release_stream,
      Coordinator::Write::Events::ReleaseSetCompensationRequestedV1.new(
        release_set_id: legacy_release_set_id,
        change_set_id: legacy_change_set_id,
        release_digest: preparation.release_digest,
        trigger_event: event_reference(trigger),
        trigger_kind: "repository_integration_failed",
        successful_integrations: [ event_reference(successful) ],
        reason: "Conflicting target branch",
        rule_version: "release-set-compensation/v1",
        requested_at: "2026-08-01T11:04:00.000001Z"
      ),
      markers: [ "release-set:#{legacy_release_set_id}" ]
    )
  end

  def persist_completion(prepared, outcome:, source_event:, successful_integrations: [])
    preparation = event_payload(prepared)
    evidence = successful_integrations.map do |integration|
      payload = event_payload(integration)
      Coordinator::Write::ReleaseSets::CompensationEvidenceV1.new(
        repository_id: payload.repository_id,
        integration_event: event_reference(integration),
        action: "revert",
        external_reference: "reverts/legacy-release/1",
        result_digest: digest("compensation"),
        producer: evidence_producer("release-reverter"),
        run_id: "legacy-compensation-run",
        compensated_at: "2026-08-01T11:05:00.000001Z"
      )
    end
    rule_version = "release-set-completion/v1"
    attributes = {
      release_set_id: legacy_release_set_id,
      release_digest: preparation.release_digest,
      outcome:,
      source_event: event_reference(source_event),
      compensation_evidence: evidence,
      rule_version:
    }
    completion_digest = legacy_release_digest_builder.call(:completion, **attributes)
    persist_payload(
      release_stream,
      Coordinator::Write::Events::ReleaseSetCompletedV1.new(
        **attributes,
        change_set_id: legacy_change_set_id,
        completion_digest:,
        completed_at: "2026-08-01T11:05:01.000001Z"
      ),
      markers: [ "release-set:#{legacy_release_set_id}" ]
    )
  end

  def plan_and_dispatch_dependencies(members, upper_position:)
    dependencies = members.flat_map do |member|
      member.values_at(:candidate, :manifest, :registration, :submission, :verified, :authorization, :observation)
    end
    dependencies.each { expect(plan(_1, upper_position:)).to be_success }
    dependencies.each { expect(dispatch(_1, upper_position:)).to be_success }
  end

  def plan_merge_dependencies(members, upper_position:)
    members.flat_map do |member|
      member.values_at(:candidate, :manifest, :registration, :submission, :verified, :authorization, :observation)
    end.each { expect(plan(_1, upper_position:)).to be_success }
  end

  def persist_scope_roots
    persist_raw(stream("DevelopmentPlanning", "ChangeSet", legacy_change_set_id), type: "ChangeSetCreated")
    2.times do |index|
      persist_raw(stream("DevelopmentPlanning", "Repository", repository_id(index)), type: "RepositoryRegistered")
      persist_raw(stream("DevelopmentExecution", "WorkItem", work_item_id(index)), type: "WorkItemCreated")
      persist_raw(stream("DevelopmentExecution", "Attempt", attempt_id(index)), type: "AttemptAuthorized")
    end
  end

  def candidate_payload(index)
    Coordinator::Write::Events::CandidateSubmittedV2.new(
      candidate_id: candidate_id(index),
      change_set_id: legacy_change_set_id,
      work_item_id: work_item_id(index),
      attempt_id: attempt_id(index),
      agent_id: "legacy-release-agent",
      repository_id: repository_id(index),
      target_branch: "main",
      object_format: "sha1",
      base_commit_oid: base_oid(index),
      head_commit_oid: head_oid(index),
      checkpoint_kind: "final",
      lease_set_id: SecureRandom.uuid_v7,
      lease_policy_version: Coordinator::Write::LeaseResourceV2::POLICY_VERSION,
      lease_references: [
        Coordinator::Write::LeaseReferenceV2.new(
          lease_id: SecureRandom.uuid_v7,
          resource_id: SecureRandom.uuid_v7,
          resource_kind: "file",
          resource_path: "lib/release_#{index + 1}.rb",
          base_blob_oid: base_oid(index),
          fencing_token: 1
        )
      ],
      manifest_digest: manifest_digest(index),
      build_context_digest: nil,
      evidence_status: "attributed_unverified",
      submitted_at: "2026-08-01T10:00:0#{index}.000001Z"
    )
  end

  def manifest_payload(index)
    Coordinator::Write::Events::CandidateChangeManifestCapturedV1.new(
      candidate_id: candidate_id(index),
      repository_id: repository_id(index),
      target_branch: "main",
      object_format: "sha1",
      base_commit_oid: base_oid(index),
      head_commit_oid: head_oid(index),
      evidence_revision: 1,
      policy_version: Coordinator::Write::Candidates::ChangeManifestDocumentV1::SCHEMA,
      manifest_digest: manifest_digest(index),
      files: [
        Coordinator::Write::Candidates::ManifestFileV1.new(
          status: "modified",
          old_path: "lib/release_#{index + 1}.rb",
          new_path: "lib/release_#{index + 1}.rb",
          old_blob_oid: base_oid(index),
          new_blob_oid: head_oid(index),
          old_mode: "100644",
          new_mode: "100644"
        )
      ],
      collector: Coordinator::Write::Candidates::EvidenceCollectorV1.new(
        kind: "agent",
        id: "legacy-release-agent",
        collector_version: "git-diff-tree/v1"
      ),
      captured_at: "2026-08-01T10:01:0#{index}.000001Z"
    )
  end

  def snapshot_payload(index, candidate:, manifest:)
    Coordinator::Write::Events::MergeSnapshotRegisteredV1.new(
      merge_snapshot_id: snapshot_id(index),
      repository_id: repository_id(index),
      target_branch: "main",
      object_format: "sha1",
      target_base_commit_oid: base_oid(index),
      ordered_candidates: [ candidate_member(index, candidate:, manifest:) ],
      merge_commit_oid: merge_oid(index),
      producer: Coordinator::Write::MergeSnapshots::ProducerV1.new(name: "git-merge", version: "2.47.0"),
      run_id: "legacy-merge-run-#{index + 1}",
      produced_at: "2026-08-01T10:02:0#{index}.000001Z",
      snapshot_digest: snapshot_digest(index),
      policy_version: "merge-snapshot-registration/v1",
      evidence_status: "attributed_unverified",
      registered_at: "2026-08-01T10:02:1#{index}.000001Z"
    )
  end

  def candidate_member(index, candidate:, manifest:)
    Coordinator::Write::MergeSnapshots::CandidateMemberV1.new(
      candidate_id: candidate_id(index),
      change_set_id: legacy_change_set_id,
      work_item_id: work_item_id(index),
      attempt_id: attempt_id(index),
      repository_id: repository_id(index),
      target_branch: "main",
      object_format: "sha1",
      base_commit_oid: base_oid(index),
      head_commit_oid: head_oid(index),
      manifest_digest: manifest_digest(index),
      candidate_event: event_reference(candidate),
      manifest_event: event_reference(manifest)
    )
  end

  def source_snapshot_state(index, registration:, candidate:, manifest:)
    Coordinator::Write::MergeSnapshots::StateV2.new(
      merge_snapshot_id: snapshot_id(index),
      repository_id: repository_id(index),
      target_branch: "main",
      object_format: "sha1",
      target_base_commit_oid: base_oid(index),
      merge_commit_oid: merge_oid(index),
      ordered_candidates: [ candidate_member(index, candidate:, manifest:) ],
      producer: "git-merge",
      run_id: "legacy-merge-run-#{index + 1}",
      produced_at: "2026-08-01T10:02:0#{index}.000001Z",
      snapshot_digest: snapshot_digest(index),
      registration_event: event_reference(registration)
    )
  end

  def verification_submission_payload(index, registration:, state:)
    Coordinator::Write::Events::MergeSnapshotVerificationSubmittedV1.new(
      merge_snapshot_id: snapshot_id(index),
      snapshot: Coordinator::Write::MergeSnapshotVerifications::SnapshotEvidenceV1.new(
        snapshot: state,
        event: event_reference(registration)
      ),
      verification_id: verification_id(index),
      policy_version: "merge-snapshot-verification/v1",
      assessment: verification_assessment(index),
      verification_input_digest: verification_input_digest(index),
      submitted_at: "2026-08-01T10:03:0#{index}.000001Z"
    )
  end

  def verification_assessment(index)
    Coordinator::Write::MergeSnapshotVerifications::AssessmentV1.new(
      evidence_kind: "combined_tests",
      producer: Coordinator::Write::MergeSnapshotVerifications::ProducerV1.new(
        name: "rspec",
        version: "3.13.0"
      ),
      run_id: "legacy-verification-run-#{index + 1}",
      test_suite_digest: digest("merge-test-suite-#{index}"),
      environment_digest: digest("merge-environment-#{index}"),
      result_digest: digest("merge-result-#{index}"),
      conclusion: "passed",
      findings: [],
      produced_at: "2026-08-01T10:03:0#{index}.000001Z"
    )
  end

  def verified_payload(index, registration:, state:, submission:)
    Coordinator::Write::Events::MergeSnapshotVerifiedV1.new(
      merge_snapshot_id: snapshot_id(index),
      snapshot: Coordinator::Write::MergeSnapshotVerifications::SnapshotEvidenceV1.new(
        snapshot: state,
        event: event_reference(registration)
      ),
      policy_version: "merge-snapshot-verification/v1",
      selected_verification: Coordinator::Write::MergeSnapshotVerifications::VerificationDecisionReferenceV1.new(
        verification_id: verification_id(index),
        evidence_kind: "combined_tests",
        conclusion: "passed",
        result_digest: digest("merge-result-#{index}"),
        verification_input_digest: verification_input_digest(index),
        event: event_reference(submission)
      ),
      verification_digest: merge_verification_digest(index),
      verified_at: "2026-08-01T10:04:0#{index}.000001Z"
    )
  end

  def snapshot_binding(index, registration:, verified:)
    Coordinator::Write::MergeAuthorizations::SnapshotBindingV1.new(
      registration_event: event_reference(registration),
      snapshot_digest: snapshot_digest(index),
      verification_event: event_reference(verified),
      verification_digest: merge_verification_digest(index)
    )
  end

  def authorization_payload(index, registration:, state:, binding:)
    Coordinator::Write::Events::MergeAuthorizationGrantedV1.new(
      authorization_id: authorization_id(index),
      merge_snapshot_id: snapshot_id(index),
      policy_version: "merge-authorization/v1",
      snapshot_binding: binding,
      expected_impact_policy: nil,
      evaluation: authorization_evaluation(index, registration:, state:),
      input_digest: digest("authorization-input-#{index}"),
      decision_digest: decision_digest(index),
      decided_at: "2026-08-01T10:05:0#{index}.000001Z"
    )
  end

  def authorization_evaluation(index, registration:, state:)
    Coordinator::Write::MergeAuthorizations::EvaluationV1.new(
      merge_snapshot_id: snapshot_id(index),
      snapshot: Coordinator::Write::MergeAuthorizations::SnapshotEvidenceV1.new(
        registration: state,
        registration_event: event_reference(registration),
        verification: nil,
        verification_event: nil
      ),
      target_base_observation: Coordinator::Write::MergeAuthorizations::TargetBaseObservationV1.new(
        repository_id: repository_id(index),
        target_branch: "main",
        object_format: "sha1",
        commit_oid: base_oid(index),
        observer: Coordinator::Write::MergeSnapshotVerifications::ProducerV1.new(
          name: "git-fetch",
          version: "2.47.0"
        ),
        run_id: "legacy-target-base-run-#{index + 1}",
        observed_at: "2026-08-01T10:04:3#{index}.000001Z"
      ),
      current_policy: nil,
      candidates: [],
      work_item_progress: [],
      obligations: [],
      reasons: []
    )
  end

  def observation_payload(index, binding:, authorization:)
    Coordinator::Write::Events::MergeObservedV1.new(
      merge_snapshot_id: snapshot_id(index),
      authorization_event: event_reference(authorization),
      authorization_decision_digest: decision_digest(index),
      snapshot_binding: binding,
      repository_id: repository_id(index),
      target_branch: "main",
      object_format: "sha1",
      target_before_commit_oid: base_oid(index),
      target_after_commit_oid: merge_oid(index),
      observer: Coordinator::Write::MergeObservations::ObserverV1.new(
        name: "git-provider-webhook",
        version: "2026-08"
      ),
      run_id: "legacy-observation-run-#{index + 1}",
      observed_at: "2026-08-01T10:06:0#{index}.000001Z",
      observation_digest: observation_digest(index),
      policy_version: "merge-observation/v1",
      evidence_status: "attributed_unverified",
      recorded_at: "2026-08-01T10:06:1#{index}.000001Z"
    )
  end

  def integration_failure
    Coordinator::Write::ReleaseSets::IntegrationFailureV1.new(
      code: "merge_conflict",
      summary: "Conflicting target branch",
      producer: evidence_producer("release-integrator"),
      run_id: "legacy-failed-integration-run",
      result_digest: digest("failed-integration"),
      occurred_at: "2026-08-01T11:02:00.000001Z"
    )
  end

  def verification_evidence(outcome)
    Coordinator::Write::ReleaseSets::VerificationEvidenceV1.new(
      producer: evidence_producer("release-suite"),
      run_id: "legacy-release-verification-run",
      environment_digest: digest("release-environment"),
      result_digest: digest("release-verification-#{outcome}"),
      outcome:,
      findings: [],
      produced_at: "2026-08-01T11:03:00.000001Z"
    )
  end

  def evidence_producer(name)
    Coordinator::Write::ReleaseSets::EvidenceProducerV1.new(name:, version: "1.0.0")
  end

  def plan(source_event, upper_position:)
    planner.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event:
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
            "actor_id" => "legacy-release-agent",
            "recorded_by" => "coordinator",
            "policy_version" => "legacy-policy/v1"
          },
          markers:,
          correlation_id: source_correlation_id
        )
      ]
    ).sole
  end

  def event_payload(event)
    Coordinator::Write::HistoryMigrations::LegacyEventSchemaRegistry.new.load(
      type: event.type,
      schema_version: event.metadata.fetch("schema_version"),
      data: event.data
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

  def read_target(target_stream)
    target_store.read(
      target_stream,
      Coordinator::Write::EventQueries::RELEASE_SET_LIFECYCLE
    )
  end

  def release_stream
    stream("DevelopmentIntegration", "ReleaseSet", legacy_release_set_id)
  end

  def candidate_stream(index)
    stream("DevelopmentIntegration", "Candidate", candidate_id(index))
  end

  def snapshot_stream(index)
    stream("DevelopmentIntegration", "MergeSnapshot", snapshot_id(index))
  end

  def verification_stream(index)
    stream("DevelopmentIntegration", "MergeVerification", verification_id(index))
  end

  def authorization_stream(index)
    stream("DevelopmentIntegration", "MergeAuthorization", authorization_id(index))
  end

  def stream(context, stream_name, stream_id)
    Coordinator::Write::StreamReference.new(context:, stream_name:, stream_id:)
  end

  def digest(label)
    "sha256:#{Digest::SHA256.hexdigest(label)}"
  end

  def legacy_release_digest_builder
    @legacy_release_digest_builder ||=
      Coordinator::Write::HistoryMigrations::ReleaseSetLegacyDigestBuilder.new
  end

  def repository_id(index)
    @repository_ids ||= 2.times.map { SecureRandom.uuid_v7 }
    @repository_ids.fetch(index)
  end

  def candidate_id(index) = "legacy-release-candidate-#{index + 1}"
  def work_item_id(index) = "legacy-release-work-item-#{index + 1}"
  def attempt_id(index) = "legacy-release-attempt-#{index + 1}"
  def snapshot_id(index) = "legacy-release-snapshot-#{index + 1}"
  def verification_id(index)
    @verification_ids ||= 2.times.map { SecureRandom.uuid_v7 }
    @verification_ids.fetch(index)
  end
  def authorization_id(index)
    @authorization_ids ||= 2.times.map { SecureRandom.uuid_v7 }
    @authorization_ids.fetch(index)
  end
  def base_oid(index) = (index.zero? ? "a" : "b") * 40
  def head_oid(index) = (index.zero? ? "c" : "d") * 40
  def merge_oid(index) = (index.zero? ? "e" : "f") * 40
  def manifest_digest(index) = digest("manifest-#{index}")
  def snapshot_digest(index) = digest("snapshot-#{index}")
  def verification_input_digest(index) = digest("verification-input-#{index}")
  def merge_verification_digest(index) = digest("merge-verification-#{index}")
  def decision_digest(index) = digest("authorization-decision-#{index}")
  def observation_digest(index) = digest("merge-observation-#{index}")
end
