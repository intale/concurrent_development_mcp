# frozen_string_literal: true

RSpec.describe "history migration verification-obligation transformers", :event_store do
  let(:source_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:target_store) do
    Coordinator::Write::EventStore.new(client: PgEventstore.client(:migration_target))
  end
  let(:registry) { Coordinator::Container["history_migrations.transformer_registry"] }
  let(:planner) { Coordinator::Container["history_migrations.event_planning_dispatcher"] }
  let(:dispatcher) { Coordinator::Container["history_migrations.event_dispatcher"] }
  let(:stream_allocator) { Coordinator::Container["history_migrations.stream_identity_allocator"] }
  let(:process_step_planner) { Coordinator::Container["history_migrations.process_step_planner"] }
  let(:target_event_planner) { Coordinator::Container["history_migrations.target_event_planner"] }
  let(:matcher) { Coordinator::Write::CandidateObligations::Matcher.new }
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:correlation_id) { SecureRandom.uuid_v7 }
  let(:legacy_repository_id) { SecureRandom.uuid_v7 }
  let(:legacy_change_set_id) { "legacy-obligation-change-set" }
  let(:legacy_decision_id) { "legacy-obligation-policy" }
  let(:legacy_partition_id) { "changeset:#{legacy_change_set_id}:candidate" }
  let(:legacy_obligation_id) { "sha256:#{'0' * 64}" }
  let(:legacy_scan_id) { "sha256:#{'1' * 64}" }
  let(:validity_digest) { digest("validity") }
  let(:assessment_digest) { digest("assessment") }
  let(:outcome_digest) { digest("outcome") }
  let(:rule_version) { "candidate-compatibility-obligation/v1" }
  let(:invalidation_rule_version) { "verification-obligation-validity/v1" }

  before { persist_scope_roots }

  it "splits creation and satisfaction while preserving only fact-specific policy metadata" do
    dependencies = persist_dependencies
    obligation = persist_obligation(dependencies)
    claim = persist_payload(obligation_stream, claim_payload(obligation))
    evidence = persist_payload(obligation_stream, evidence_payload(obligation, claim, conclusion: "passed"))
    satisfied = persist_payload(obligation_stream, satisfied_payload(obligation, evidence))
    upper_position = satisfied.global_position
    plan_dependencies(dependencies, upper_position:)
    [ obligation, claim, evidence, satisfied ].each do |event|
      expect(plan(event, upper_position:)).to be_success
    end

    creation_facts = transform(obligation, upper_position:).value!
    claim_fact = transform(claim, upper_position:).value!.sole
    evidence_fact = transform(evidence, upper_position:).value!.sole
    satisfied_facts = transform(satisfied, upper_position:).value!

    expect(creation_facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::VerificationObligationCreatedV2,
      Coordinator::Write::Events::VerificationObligationAddedToChangeSetV1,
      Coordinator::Write::Events::VerificationObligationSourceCandidateAssignedV1,
      Coordinator::Write::Events::VerificationObligationTargetCandidateAssignedV1
    ])
    expect(creation_facts.first.target_stream.stream_id).to match(
      Coordinator::Shared::Types::UUID_V7_PATTERN
    )
    expect(creation_facts.first.target_stream.stream_id).not_to eq(legacy_obligation_id)
    expect(creation_facts.map(&:target_stream).uniq.one?).to be(true)
    expect(creation_facts.first.event).to have_attributes(
      obligation_id: creation_facts.first.target_stream.stream_id,
      reasons: [ "semantic_key_match" ],
      required_evidence: %w[combined_tests],
      enforcement: "merge_gate"
    )
    expect(creation_facts.drop(1).map { _1.event.to_h.keys }).to eq([
      %i[obligation_id change_set_id],
      %i[obligation_id candidate_id],
      %i[obligation_id candidate_id]
    ])
    expect(creation_facts.drop(1).flat_map { _1.event.to_h.values }).to all(
      match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    )
    expect(creation_facts.first.metadata_extension).to have_attributes(
      policy: have_attributes(change_set_id: match(Coordinator::Shared::Types::UUID_V7_PATTERN)),
      rule_version:,
      validity_input_digest: validity_digest
    )
    expect(creation_facts.first.metadata_extension.policy.partition_event).to have_attributes(
      type: "DecisionAddedToPartition",
      stream_id: match(/^changeset:[0-9a-f-]+:candidate$/)
    )
    expect(creation_facts.first.metadata_extension.policy.head.event).to have_attributes(
      type: "DecisionActivated",
      stream_id: match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    )

    expect(claim_fact.event).to be_a(Coordinator::Write::Events::VerificationObligationClaimedV2)
    expect(claim_fact.event.to_h.keys).to contain_exactly(
      :obligation_id, :claim_id, :claimant_id, :fencing_token, :expires_at
    )
    expect(evidence_fact.event).to be_a(Coordinator::Write::Events::VerificationEvidenceSubmittedV2)
    expect(evidence_fact.metadata_extension).to have_attributes(
      assessment_input_digest: assessment_digest,
      obligation_validity_input_digest: validity_digest,
      policy: creation_facts.first.metadata_extension.policy
    )
    expect(evidence_fact.event.claim.claim_event).to have_attributes(
      type: "VerificationObligationClaimed",
      stream_id: creation_facts.first.target_stream.stream_id
    )
    expect(satisfied_facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::VerificationObligationEvidenceSelectedV1,
      Coordinator::Write::Events::VerificationObligationSatisfiedV2
    ])
    expect(satisfied_facts.last.metadata_extension).to have_attributes(
      outcome_digest:,
      policy: creation_facts.first.metadata_extension.policy
    )

    transformed = creation_facts + [ claim_fact, evidence_fact ] + satisfied_facts
    expect(transformed.flat_map(&:markers).join("\n")).not_to include("sha256:")
    expect(transformed.flat_map { _1.event.to_h.keys }).not_to include(
      :created_at, :claimed_at, :submitted_at, :satisfied_at
    )

    results = [ obligation, claim, evidence, satisfied ].map do |source_event|
      dispatch(source_event, upper_position:).value!
    end
    expect([ obligation, claim, evidence, satisfied ].map do |source_event|
      dispatch(source_event, upper_position:).value!.outcome
    end.uniq).to eq([ "existing" ])

    persisted = read_target(
      creation_facts.first.target_stream,
      event_types: %w[
        VerificationObligationCreated VerificationObligationAddedToChangeSet
        VerificationObligationSourceCandidateAssigned VerificationObligationTargetCandidateAssigned
        VerificationObligationClaimed VerificationEvidenceSubmitted
        VerificationObligationEvidenceSelected VerificationObligationSatisfied
      ],
      maximum_count: 8
    )
    expect(results.sum { _1.events.length }).to eq(8)
    expect(persisted.map(&:stream_revision)).to eq((0..7).to_a)
    expect(persisted.map(&:correlation_id).uniq).to contain_exactly(persisted.first.correlation_id)
    expect(persisted.fetch(0).metadata).to include(
      "validity_input_digest" => validity_digest,
      "rule_version" => rule_version
    )
    expect(persisted.fetch(5).metadata).to include(
      "assessment_input_digest" => assessment_digest,
      "obligation_validity_input_digest" => validity_digest
    )
    expect(persisted.last.metadata.fetch("outcome_digest")).to eq(outcome_digest)
  end

  it "migrates failed, waived, and invalidated outcomes with exact predecessor evidence" do
    dependencies = persist_dependencies(superseding: true)
    obligation = persist_obligation(dependencies)
    claim = persist_payload(obligation_stream, claim_payload(obligation))
    evidence = persist_payload(obligation_stream, evidence_payload(obligation, claim, conclusion: "failed"))
    failed = persist_payload(obligation_stream, failed_payload(obligation, evidence))
    waived = persist_payload(obligation_stream, waived_payload(obligation, failed))
    invalidated = persist_payload(
      obligation_stream,
      invalidated_payload(obligation, waived, dependencies.fetch(:superseding_partition_event))
    )
    upper_position = invalidated.global_position
    plan_dependencies(dependencies, upper_position:)
    [ obligation, claim, evidence, failed, waived, invalidated ].each do |event|
      expect(plan(event, upper_position:)).to be_success
    end

    failed_facts = transform(failed, upper_position:).value!
    waived_fact = transform(waived, upper_position:).value!.sole
    invalidated_fact = transform(invalidated, upper_position:).value!.sole

    expect(failed_facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::VerificationObligationEvidenceSelectedV1,
      Coordinator::Write::Events::VerificationObligationFailedV2
    ])
    expect(failed_facts.last.event.reason).to be_nil
    expect(failed_facts.last.metadata_extension).to have_attributes(
      outcome_digest:,
      policy: be_a(Coordinator::Write::CandidateObligations::ImpactPolicyEvidenceV1)
    )
    expect(waived_fact.event).to have_attributes(
      obligation_id: failed_facts.last.event.obligation_id,
      reason: have_attributes(code: "accepted_risk")
    )
    expect(waived_fact.metadata_extension).to have_attributes(
      waiver_input_digest: digest("waiver"),
      policy: failed_facts.last.metadata_extension.policy
    )
    expect(invalidated_fact.event).to have_attributes(
      obligation_id: failed_facts.last.event.obligation_id,
      reason: "policy_partition_advanced",
      superseding_partition_event: have_attributes(type: "DecisionAddedToPartition")
    )
    expect(invalidated_fact.metadata_extension).to have_attributes(
      invalidated_policy: failed_facts.last.metadata_extension.policy,
      invalidation_digest: digest("invalidation"),
      rule_version: invalidation_rule_version
    )
    expect([ *failed_facts, waived_fact, invalidated_fact ].flat_map { _1.event.to_h.keys }).not_to include(
      :failed_at, :waived_at, :invalidated_at, :previous_status, :previous_terminal_event
    )

    [ obligation, claim, evidence, failed, waived, invalidated ].each do |source_event|
      expect(dispatch(source_event, upper_position:)).to be_success
    end
  end

  it "moves a validity scan to a UUIDv7 stream and trims checkpoint bookkeeping" do
    dependencies = persist_dependencies(superseding: true)
    started = persist_payload(
      scan_stream,
      scan_started_payload(dependencies.fetch(:superseding_partition_event)),
      markers: [ "verification-obligation-validity-scan:#{legacy_scan_id}" ]
    )
    progressed = persist_payload(scan_stream, scan_progressed_payload(started, dependencies))
    completed = persist_payload(scan_stream, scan_completed_payload(started, progressed, dependencies))
    upper_position = completed.global_position
    plan_dependencies(dependencies, upper_position:)
    [ started, progressed, completed ].each do |event|
      expect(plan(event, upper_position:)).to be_success
    end

    started_facts = transform(started, upper_position:).value!
    progressed_fact = transform(progressed, upper_position:).value!.sole
    completed_fact = transform(completed, upper_position:).value!.sole

    expect(started_facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::VerificationObligationValidityScanStartedV2,
      Coordinator::Write::Events::VerificationObligationValidityScanSourceLinkedV1
    ])
    expect(started_facts.first.target_stream.stream_id).to match(
      Coordinator::Shared::Types::UUID_V7_PATTERN
    )
    expect(started_facts.first.target_stream.stream_id).not_to eq(legacy_scan_id)
    expect(started_facts.first.event).to have_attributes(
      scan_id: started_facts.first.target_stream.stream_id,
      change_set_id: match(Coordinator::Shared::Types::UUID_V7_PATTERN),
      from_position: 0,
      to_position: 100,
      page_size: 50
    )
    expect(started_facts.last.event).to have_attributes(
      role: "superseding_partition",
      source: have_attributes(type: "DecisionAddedToPartition")
    )
    expect(progressed_fact.event).to have_attributes(
      scan_id: started_facts.first.event.scan_id,
      page_number: 1,
      next_from_position: 50,
      page_size: 50
    )
    expect(completed_fact.event.to_h).to eq(scan_id: started_facts.first.event.scan_id)
    expect([ *started_facts, progressed_fact, completed_fact ].flat_map { _1.event.to_h.keys }).not_to include(
      :started_at, :progressed_at, :completed_at, :page_obligation_count,
      :total_obligation_count, :page_count, :previous_checkpoint
    )

    [ started, progressed, completed ].each do |source_event|
      expect(dispatch(source_event, upper_position:)).to be_success
    end
    persisted = read_target(
      started_facts.first.target_stream,
      event_types: %w[
        VerificationObligationValidityScanStarted VerificationObligationValidityScanSourceLinked
        VerificationObligationValidityScanProgressed VerificationObligationValidityScanCompleted
      ],
      maximum_count: 4
    )
    expect(persisted.map(&:stream_revision)).to eq((0..3).to_a)
  end

  it "fails closed for duplicate selected evidence and a forged Candidate subject" do
    dependencies = persist_dependencies
    obligation = persist_obligation(dependencies)
    claim = persist_payload(obligation_stream, claim_payload(obligation))
    evidence = persist_payload(obligation_stream, evidence_payload(obligation, claim, conclusion: "passed"))
    duplicate = satisfied_payload(obligation, evidence)
    duplicate = duplicate.class.new(duplicate.to_h.merge(selected_evidence: [ *duplicate.selected_evidence ] * 2))
    duplicate_event = persist_payload(obligation_stream, duplicate)
    upper_position = duplicate_event.global_position
    plan_dependencies(dependencies, upper_position:)
    [ obligation, claim, evidence ].each { expect(plan(_1, upper_position:)).to be_success }

    duplicate_result = transform(duplicate_event, upper_position:)
    expect(duplicate_result).to be_failure
    expect(duplicate_result.failure).to have_attributes(code: :ambiguous_source_reference)
    expect(duplicate_result.failure.message).to include("duplicate identities")

    forged_subject = event_payload(obligation).source_candidate.new(head_commit_oid: "f" * 40)
    forged_payload = event_payload(obligation).class.new(
      event_payload(obligation).to_h.merge(source_candidate: forged_subject)
    )
    forged_stream = stream("DevelopmentIntegration", "VerificationObligation", "legacy-forged-obligation")
    forged_event = persist_payload(
      forged_stream,
      forged_payload.new(obligation_id: "legacy-forged-obligation"),
      markers: [ "verification-obligation:legacy-forged-obligation" ]
    )

    forged_result = transform(forged_event, upper_position: forged_event.global_position)
    expect(forged_result).to be_failure
    expect(forged_result.failure).to have_attributes(
      code: :ambiguous_source_reference,
      event_type: "VerificationObligationCreated",
      source_event_id: forged_event.id
    )
  end

  private

  def persist_scope_roots
    persist_raw(stream("DevelopmentPlanning", "Repository", legacy_repository_id), type: "RepositoryRegistered")
    persist_raw(stream("DevelopmentPlanning", "ChangeSet", legacy_change_set_id), type: "ChangeSetCreated")
    %w[source target].each do |role|
      persist_raw(stream("DevelopmentExecution", "WorkItem", work_item_id(role)), type: "WorkItemCreated")
      persist_raw(stream("DevelopmentExecution", "Attempt", attempt_id(role)), type: "AttemptAuthorized")
    end
  end

  def persist_dependencies(superseding: false)
    source = persist_candidate("source", produces: [ "api:checkout" ])
    target = persist_candidate("target", consumes: [ "api:checkout" ])
    decision_event = persist_raw(
      stream("HumanGuidance", "Decision", legacy_decision_id),
      type: "DecisionActivated"
    )
    head = Coordinator::Write::Decisions::DecisionHeadV1.new(
      decision_id: legacy_decision_id,
      decision_revision: decision_event.stream_revision,
      event: event_reference(decision_event)
    )
    partition = Coordinator::Write::Decisions::DecisionPartitionV1.new(
      partition_id: legacy_partition_id,
      topic_root: "candidate",
      anchor_kind: "changeset",
      anchor_id: legacy_change_set_id
    )
    partition_event = persist_payload(
      stream("HumanGuidance", "DecisionPartition", legacy_partition_id),
      partition_payload(partition:, head:, revision: 0, change_kind: "activated")
    )
    superseding_partition_event = if superseding
      persist_payload(
        stream("HumanGuidance", "DecisionPartition", legacy_partition_id),
        partition_payload(partition:, head:, revision: 1, change_kind: "corrected")
      )
    end
    policy = Coordinator::Write::CandidateObligations::ImpactPolicyEvidenceV1.new(
      partition_event: event_reference(partition_event),
      partition:,
      head:,
      definition_digest: digest("policy-definition"),
      change_set_id: legacy_change_set_id,
      required_evidence: %w[combined_tests],
      enforcement: "merge_gate",
      valid_from: "2026-08-30T11:59:00.000000Z"
    )
    {
      source:, target:, decision_event:, partition_event:, superseding_partition_event:, policy:
    }
  end

  def persist_candidate(role, produces: [], consumes: [])
    candidate_stream = stream("DevelopmentIntegration", "Candidate", candidate_id(role))
    submitted_payload = candidate_payload(role)
    HistoryMigrationCandidateFixture.persist_reservation(event_store: source_store, candidate: submitted_payload)
    submitted = persist_payload(candidate_stream, submitted_payload)
    manifest_payload = candidate_manifest_payload(role)
    manifest = persist_payload(candidate_stream, manifest_payload)
    surface_payload = candidate_surface_payload(role, produces:, consumes:)
    surface = persist_payload(candidate_stream, surface_payload)
    registration_payload = candidate_registration_payload(role, submitted, manifest, surface)
    registration = persist_payload(candidate_registry_stream, registration_payload)
    subject = candidate_subject(
      role,
      submitted:,
      manifest:,
      surface:,
      registration:
    )
    evidence = Coordinator::Write::CandidateObligations::CandidateEvidenceV1.new(
      registration: registration_payload,
      registration_event: event_reference(registration),
      candidate: submitted_payload,
      manifest: manifest_payload,
      build_context: nil,
      surface: surface_payload,
      subject:
    )
    { submitted:, manifest:, surface:, registration:, subject:, evidence: }
  end

  def candidate_payload(role)
    Coordinator::Write::Events::CandidateSubmittedV2.new(
      candidate_id: candidate_id(role),
      change_set_id: legacy_change_set_id,
      work_item_id: work_item_id(role),
      attempt_id: attempt_id(role),
      agent_id: "legacy-agent-#{role}",
      repository_id: legacy_repository_id,
      target_branch: "main",
      object_format: "sha1",
      base_commit_oid: "a" * 40,
      head_commit_oid: head_oid(role),
      checkpoint_kind: "final",
      lease_set_id: SecureRandom.uuid_v7,
      lease_policy_version: Coordinator::Write::LeaseResourceV2::POLICY_VERSION,
      lease_references: [
        Coordinator::Write::LeaseReferenceV2.new(
          lease_id: SecureRandom.uuid_v7,
          resource_id: SecureRandom.uuid_v7,
          resource_kind: "file",
          resource_path: "lib/#{role}.rb",
          base_blob_oid: "a" * 40,
          fencing_token: 1
        )
      ],
      manifest_digest: manifest_digest(role),
      build_context_digest: nil,
      evidence_status: "attributed_unverified",
      submitted_at: "2026-08-30T12:00:00.000000Z"
    )
  end

  def candidate_manifest_payload(role)
    Coordinator::Write::Events::CandidateChangeManifestCapturedV1.new(
      candidate_id: candidate_id(role),
      repository_id: legacy_repository_id,
      target_branch: "main",
      object_format: "sha1",
      base_commit_oid: "a" * 40,
      head_commit_oid: head_oid(role),
      evidence_revision: 1,
      policy_version: Coordinator::Write::Candidates::ChangeManifestDocumentV1::SCHEMA,
      manifest_digest: manifest_digest(role),
      files: [ manifest_file(role) ],
      collector: collector(role),
      captured_at: "2026-08-30T12:01:00.000000Z"
    )
  end

  def candidate_surface_payload(role, produces:, consumes:)
    Coordinator::Write::Events::CandidateImpactSurfaceDerivedV1.new(
      candidate_id: candidate_id(role),
      change_set_id: legacy_change_set_id,
      work_item_id: work_item_id(role),
      attempt_id: attempt_id(role),
      repository_id: legacy_repository_id,
      target_branch: "main",
      object_format: "sha1",
      head_commit_oid: head_oid(role),
      evidence_revision: 1,
      policy_version: Coordinator::Write::Candidates::ImpactSurfaceDocumentV1::SCHEMA,
      surface_digest: surface_digest(role),
      manifest_digest: manifest_digest(role),
      build_context_digest: nil,
      produces: produces.map do |key|
        Coordinator::Write::Candidates::ImpactTransitionV1.new(
          impact_key: key,
          before: nil,
          after: "changed"
        )
      end,
      consumes: consumes.map do |key|
        Coordinator::Write::Candidates::ImpactObservationV1.new(impact_key: key, value: "observed")
      end,
      may_affect: [],
      assumes: [],
      analyzer: Coordinator::Write::Candidates::ImpactAnalyzerV1.new(
        kind: "agent",
        id: "legacy-agent-#{role}",
        analyzer_version: "candidate-impact/v1"
      ),
      evidence_status: "attributed_unverified",
      derived_at: "2026-08-30T12:02:00.000000Z"
    )
  end

  def candidate_registration_payload(role, submitted, manifest, surface)
    Coordinator::Write::Events::CandidateImpactSurfaceRegisteredV1.new(
      candidate_id: candidate_id(role),
      change_set_id: legacy_change_set_id,
      work_item_id: work_item_id(role),
      attempt_id: attempt_id(role),
      repository_id: legacy_repository_id,
      target_branch: "main",
      object_format: "sha1",
      base_commit_oid: "a" * 40,
      head_commit_oid: head_oid(role),
      candidate_event: event_reference(submitted),
      manifest_event: event_reference(manifest),
      build_context_event: nil,
      surface_event: event_reference(surface),
      surface_digest: surface_digest(role),
      index_policy_version: Coordinator::Write::Candidates::ImpactIndexMarkerBuilder::POLICY_VERSION,
      registered_at: "2026-08-30T12:03:00.000000Z"
    )
  end

  def candidate_subject(role, submitted:, manifest:, surface:, registration:)
    Coordinator::Write::CandidateObligations::CandidateSubjectV1.new(
      candidate_id: candidate_id(role),
      change_set_id: legacy_change_set_id,
      work_item_id: work_item_id(role),
      attempt_id: attempt_id(role),
      repository_id: legacy_repository_id,
      target_branch: "main",
      object_format: "sha1",
      base_commit_oid: "a" * 40,
      head_commit_oid: head_oid(role),
      manifest_digest: manifest_digest(role),
      build_context_digest: nil,
      surface_digest: surface_digest(role),
      candidate_event: event_reference(submitted),
      manifest_event: event_reference(manifest),
      build_context_event: nil,
      surface_event: event_reference(surface),
      registration_event: event_reference(registration)
    )
  end

  def persist_obligation(dependencies)
    source = dependencies.fetch(:source)
    target = dependencies.fetch(:target)
    reasons = matcher.call(source: source.fetch(:evidence), target: target.fetch(:evidence))
    payload = Coordinator::Write::Events::VerificationObligationCreatedV1.new(
      obligation_id: legacy_obligation_id,
      kind: "candidate_compatibility",
      status: "open",
      change_set_id: legacy_change_set_id,
      source_candidate: source.fetch(:subject),
      target_candidate: target.fetch(:subject),
      reasons:,
      required_evidence: %w[combined_tests],
      enforcement: "merge_gate",
      policy: dependencies.fetch(:policy),
      validity_input_digest: validity_digest,
      rule_version:,
      created_at: "2026-08-30T12:04:00.000000Z"
    )
    persist_payload(
      obligation_stream,
      payload,
      markers: [ "verification-obligation:#{legacy_obligation_id}" ]
    )
  end

  def claim_payload(obligation)
    Coordinator::Write::Events::VerificationObligationClaimedV1.new(
      obligation_id: legacy_obligation_id,
      obligation_event: event_reference(obligation),
      claim_id: SecureRandom.uuid_v7,
      claimant_id: "legacy-agent",
      fencing_token: 1,
      claimed_at: "2026-08-30T12:05:00.000000Z",
      expires_at: "2026-08-30T12:10:00.000000Z"
    )
  end

  def evidence_payload(obligation, claim, conclusion:)
    claim_data = event_payload(claim)
    creation = event_payload(obligation)
    Coordinator::Write::Events::VerificationEvidenceSubmittedV1.new(
      obligation_id: legacy_obligation_id,
      obligation_event: event_reference(obligation),
      evidence_id: SecureRandom.uuid_v7,
      evidence_kind: "combined_tests",
      claim: Coordinator::Write::CompatibilityAssessments::ClaimEvidenceV1.new(
        claim_id: claim_data.claim_id,
        claimant_id: claim_data.claimant_id,
        fencing_token: claim_data.fencing_token,
        claim_event: event_reference(claim)
      ),
      source_candidate: creation.source_candidate,
      target_candidate: creation.target_candidate,
      policy: creation.policy,
      obligation_validity_input_digest: validity_digest,
      assessment: assessment(conclusion:),
      assessment_input_digest: assessment_digest,
      submitted_at: "2026-08-30T12:06:00.000000Z"
    )
  end

  def satisfied_payload(obligation, evidence)
    Coordinator::Write::Events::VerificationObligationSatisfiedV1.new(
      obligation_id: legacy_obligation_id,
      obligation_event: event_reference(obligation),
      policy: event_payload(obligation).policy,
      selected_evidence: [ evidence_decision(evidence) ],
      outcome_digest:,
      satisfied_at: "2026-08-30T12:07:00.000000Z"
    )
  end

  def failed_payload(obligation, evidence)
    Coordinator::Write::Events::VerificationObligationFailedV1.new(
      obligation_id: legacy_obligation_id,
      obligation_event: event_reference(obligation),
      policy: event_payload(obligation).policy,
      triggering_evidence: evidence_decision(evidence),
      outcome_digest:,
      failed_at: "2026-08-30T12:07:00.000000Z"
    )
  end

  def waived_payload(obligation, failed)
    Coordinator::Write::Events::VerificationObligationWaivedV1.new(
      obligation_id: legacy_obligation_id,
      obligation_event: event_reference(obligation),
      policy: event_payload(obligation).policy,
      previous_status: "failed",
      previous_terminal_event: event_reference(failed),
      reason: Coordinator::Write::VerificationObligationWaivers::ReasonV1.new(
        code: "accepted_risk",
        summary: "The user accepts the compatibility risk."
      ),
      waiver_input_digest: digest("waiver"),
      waived_at: "2026-08-30T12:08:00.000000Z"
    )
  end

  def invalidated_payload(obligation, waived, superseding_partition_event)
    Coordinator::Write::Events::VerificationObligationInvalidatedV1.new(
      obligation_id: legacy_obligation_id,
      obligation_event: event_reference(obligation),
      invalidated_policy: event_payload(obligation).policy,
      superseding_partition_event: event_reference(superseding_partition_event),
      previous_status: "waived",
      previous_terminal_event: event_reference(waived),
      reason: "policy_partition_advanced",
      invalidation_digest: digest("invalidation"),
      rule_version: invalidation_rule_version,
      invalidated_at: "2026-08-30T12:09:00.000000Z"
    )
  end

  def scan_started_payload(superseding_partition_event)
    Coordinator::Write::Events::VerificationObligationValidityScanStartedV1.new(
      scan_id: legacy_scan_id,
      change_set_id: legacy_change_set_id,
      superseding_partition_event: event_reference(superseding_partition_event),
      from_position: 0,
      to_position: 100,
      page_size: 50,
      rule_version: invalidation_rule_version,
      started_at: "2026-08-30T12:10:00.000000Z"
    )
  end

  def scan_progressed_payload(started, dependencies)
    Coordinator::Write::Events::VerificationObligationValidityScanProgressedV1.new(
      scan_id: legacy_scan_id,
      change_set_id: legacy_change_set_id,
      superseding_partition_event: event_reference(dependencies.fetch(:superseding_partition_event)),
      started_event: event_reference(started),
      previous_checkpoint: event_reference(started),
      previous_from_position: 0,
      next_from_position: 50,
      page_size: 50,
      page_number: 1,
      page_obligation_count: 4,
      total_obligation_count: 4,
      rule_version: invalidation_rule_version,
      progressed_at: "2026-08-30T12:11:00.000000Z"
    )
  end

  def scan_completed_payload(started, progressed, dependencies)
    Coordinator::Write::Events::VerificationObligationValidityScanCompletedV1.new(
      scan_id: legacy_scan_id,
      change_set_id: legacy_change_set_id,
      superseding_partition_event: event_reference(dependencies.fetch(:superseding_partition_event)),
      started_event: event_reference(started),
      previous_checkpoint: event_reference(progressed),
      previous_from_position: 50,
      final_from_position: 101,
      page_size: 50,
      page_count: 2,
      page_obligation_count: 1,
      total_obligation_count: 5,
      rule_version: invalidation_rule_version,
      completed_at: "2026-08-30T12:12:00.000000Z"
    )
  end

  def assessment(conclusion:)
    Coordinator::Write::CompatibilityAssessments::AssessmentV1.new(
      evidence_kind: "combined_tests",
      producer: Coordinator::Write::CompatibilityAssessments::ProducerV1.new(
        name: "compatibility-tests",
        version: "1.0"
      ),
      run_id: "legacy-assessment",
      test_suite_digest: digest("test-suite"),
      environment_digest: digest("environment"),
      dependency_graph_digest: digest("dependency-graph"),
      result_digest: digest("result-#{conclusion}"),
      conclusion:,
      findings: [],
      produced_at: "2026-08-30T12:06:00.000000Z"
    )
  end

  def evidence_decision(evidence)
    submission = event_payload(evidence)
    Coordinator::Write::CompatibilityAssessments::EvidenceDecisionReferenceV1.new(
      evidence_kind: submission.evidence_kind,
      evidence_id: submission.evidence_id,
      conclusion: submission.assessment.conclusion,
      result_digest: submission.assessment.result_digest,
      assessment_input_digest: submission.assessment_input_digest,
      event: event_reference(evidence)
    )
  end

  def partition_payload(partition:, head:, revision:, change_kind:)
    Coordinator::Write::Events::DecisionPartitionAdvancedV1.new(
      partition:,
      partition_revision: revision,
      decision: head,
      active_decisions: [ head ],
      change_kind:,
      advanced_at: "2026-08-30T11:58:00.000000Z"
    )
  end

  def plan_dependencies(dependencies, upper_position:)
    %i[source target].each do |role|
      %i[submitted manifest surface registration].each do |name|
        expect(plan(dependencies.fetch(role).fetch(name), upper_position:)).to be_success
      end
    end
    expect(plan_decision_reference(dependencies.fetch(:decision_event), upper_position:)).to be_success
    expect(plan(dependencies.fetch(:partition_event), upper_position:)).to be_success
    if dependencies.fetch(:superseding_partition_event)
      expect(plan(dependencies.fetch(:superseding_partition_event), upper_position:)).to be_success
    end
  end

  def plan_decision_reference(source_event, upper_position:)
    raise "source position outside test migration window" if source_event.global_position > upper_position

    allocation = stream_allocator.call(
      migration_id:,
      source_config_name: "default",
      source_event:,
      target_stream_context: "HumanGuidance",
      target_stream_name: "Decision",
      identity_role: "decision"
    )
    return allocation if allocation.failure?

    process_step = process_step_planner.call(
      source_event:,
      process_name: "history-migration-#{migration_id}",
      step_name: "activate-decision",
      subject_kind: "source-event",
      subject_id: source_event.id,
      rule_version: "history-migration-transformation/v1",
      allocate_target_entity: true
    )
    target_event_planner.call(
      migration_id:,
      source_event:,
      transformation_step: "activate-decision",
      target_stream: allocation.value!.target_stream,
      target_event_id: process_step.target_entity_id!,
      target_event_type: "DecisionActivated",
      caused_by: process_step.event
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
          correlation_id:
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

  def read_target(target_stream, event_types:, maximum_count:)
    target_store.read(
      target_stream,
      Coordinator::Write::EventReadCriteria.new(
        event_types:,
        maximum_count:,
        direction: :asc
      )
    )
  end

  def obligation_stream
    stream("DevelopmentIntegration", "VerificationObligation", legacy_obligation_id)
  end

  def scan_stream
    stream("DevelopmentIntegration", "VerificationObligationValidityScan", legacy_scan_id)
  end

  def candidate_registry_stream
    stream("DevelopmentIntegration", "CandidateImpactRegistry", legacy_change_set_id)
  end

  def stream(context, stream_name, stream_id)
    Coordinator::Write::StreamReference.new(context:, stream_name:, stream_id:)
  end

  def candidate_id(role)
    "legacy-candidate-#{role}"
  end

  def work_item_id(role)
    "legacy-work-item-#{role}"
  end

  def attempt_id(role)
    "legacy-attempt-#{role}"
  end

  def head_oid(role)
    (role == "source" ? "b" : "c") * 40
  end

  def manifest_digest(role)
    digest("manifest-#{role}")
  end

  def surface_digest(role)
    digest("surface-#{role}")
  end

  def manifest_file(role)
    Coordinator::Write::Candidates::ManifestFileV1.new(
      status: "modified",
      old_path: "lib/#{role}.rb",
      new_path: "lib/#{role}.rb",
      old_blob_oid: "a" * 40,
      new_blob_oid: head_oid(role),
      old_mode: "100644",
      new_mode: "100644"
    )
  end

  def collector(role)
    Coordinator::Write::Candidates::EvidenceCollectorV1.new(
      kind: "agent",
      id: "legacy-agent-#{role}",
      collector_version: "git-diff-tree/v1"
    )
  end

  def digest(value)
    Coordinator::Shared::CanonicalJson.new.sha256(value)
  end
end
