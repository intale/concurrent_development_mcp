# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::VerificationObligationsV1, :read_model, :event_store do
  subject(:projector) do
    described_class.new(
      source_loader:
    )
  end

  let(:repository) { Coordinator::Read::Repositories::VerificationObligations.new }
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:event_factory) { Coordinator::Write::EventFactory.new }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:obligation_id) { SecureRandom.uuid_v7 }
  let(:creation_command_id) { SecureRandom.uuid_v7 }
  let(:change_set_id) { "CS-obligation-projection" }
  let(:correlation_id) { SecureRandom.uuid_v7 }

  it "reconstructs native definition facts idempotently and rebuilds without write-side effects" do
    events = definition_events
    created = events.first
    loaded = source_loader.definition(obligation_id)
    projector.call(events)
    projector.call(events)

    first = page.items.sole
    expect(first).to have_attributes(
      obligation_id:, status: "open", claim_state: "unclaimed"
    )
    expect(first.source_candidate.to_h).to eq(loaded.document.fetch(:source_candidate))
    expect(first.target_candidate.to_h).to eq(loaded.document.fetch(:target_candidate))
    expect(first.reasons.map(&:to_h)).to eq(loaded.document.fetch(:reasons))
    expect(first.evidence).to have_attributes(
      event: event_reference(created), metadata: created.metadata,
      causation_id: created.causation_id, correlation_id: created.correlation_id,
      occurred_at: timestamp(created), persisted_at: timestamp(created)
    )
    expect(first.created_at).to eq(timestamp(created))
    expect(Coordinator::Read::VerificationObligation.find(obligation_id).updated_at).to eq(events.last.created_at)
    expect(event_store.read(streams.verification_obligation(obligation_id),
      Coordinator::Write::EventReadCriteria.new(event_types: [ "VerificationObligationCreated" ],
        maximum_count: 1, direction: :asc)).sole.id).to eq(created.id)

    original = first.to_h
    ReadModelTestSafety.clean!
    projector.call(events)
    expect(page.items.sole.to_h).to eq(original)
  end

  it "projects native fenced claims, expiry and reclaim without changing the creation cursor" do
    created = definition_events.first
    projector.call([ created ])
    first = claim_event(agent_id: "agent-blue", fencing_token: 1)
    projector.call([ first ])
    projector.call([ first ])
    expiry = event_payload(first).expires_at
    active = page(observed_at: timestamp(first)).items.sole
    expect(active).to have_attributes(status: "open", claim_state: "active")
    expect(active.claim).to have_attributes(
      claimant_id: "agent-blue", fencing_token: 1, claimed_at: timestamp(first), expires_at: expiry
    )
    expect(active.evidence.global_position).to eq(created.global_position)
    expect(page(observed_at: expiry).items.sole.claim_state).to eq("expired")

    second = claim_event(agent_id: "agent-green", fencing_token: 2, expires_at: Time.iso8601(expiry) + 300)
    projector.call([ second ])
    reclaimed = page(observed_at: expiry).items.sole
    expect(reclaimed.claim).to have_attributes(claimant_id: "agent-green", fencing_token: 2)
    expect(reclaimed.claim_state).to eq("active")
    expect(reclaimed.claim.evidence.event).to eq(event_reference(second))
  end

  it "patches claims in delivered order without a revision skip or independent-column replacement" do
    record = create(:coordinator_read_verification_obligation, obligation_id:, change_set_id:)
    first = claim_event(agent_id: "agent-blue", fencing_token: 1)
    second = claim_event(agent_id: "agent-green", fencing_token: 2)
    original = record.obligation
    projector.call([ second, first ])
    expect(record.reload.claimant_id).to eq("agent-blue")
    expect(record.obligation).to eq(original)
    expect(Coordinator::Read::ProcessedProjectionEvent.count).to eq(0)
  end

  it "keeps partial evidence available and reconstructs selected native satisfaction on rebuild" do
    events = definition_events
    claim = claim_event
    first = evidence_event(claim:, evidence_kind: "combined_tests", conclusion: "passed")
    second = evidence_event(claim:, evidence_kind: "contract_compatibility_review", conclusion: "passed")
    selections = [ first, second ].map { selection_event(event_payload(_1).evidence_id) }
    satisfied = outcome_event("satisfied")

    partial_progress = progress_events(count: 1, passed: [ "combined_tests" ], missing: [ "contract_compatibility_review" ])
    projector.call([ *events, claim, first, *partial_progress ])
    projector.call([ first ])
    partial = page.items.sole
    expect(partial).to have_attributes(status: "open", outcome: nil)
    expect(partial.progress).to have_attributes(
      passed_evidence_kinds: [ "combined_tests" ],
      missing_evidence_kinds: [ "contract_compatibility_review" ], evidence_count: 1
    )
    expect(partial.submitted_evidence.sole).to have_attributes(
      assessment_input_digest: first.metadata.fetch("assessment_input_digest"),
      submitted_at: timestamp(first), source_candidate: Coordinator::Write::CandidateObligations::CandidateSubjectV1.new(source_loader.definition(obligation_id).document.fetch(:source_candidate))
    )

    complete_progress = progress_events(count: 2, passed: %w[combined_tests contract_compatibility_review], missing: [])
    projector.call([ second, *complete_progress, *selections, satisfied ])
    observed = page(status: "satisfied").items.sole
    expect(observed.outcome).to have_attributes(
      satisfied_at: timestamp(satisfied), outcome_digest: satisfied.metadata.fetch("outcome_digest")
    )
    expect(observed.outcome.selected_evidence.map(&:evidence_id)).to eq(
      [ first, second ].map { event_payload(_1).evidence_id }
    )
    expect(observed.progress).to have_attributes(evidence_count: 2, missing_evidence_kinds: [])
    expect(observed.outcome.evidence.correlation_id).to eq(correlation_id)

    original = observed.to_h
    ReadModelTestSafety.clean!
    projector.call([ *events, claim, first, *partial_progress, second, *complete_progress, *selections, satisfied ])
    expect(page(status: "satisfied").items.sole.to_h).to eq(original)
  end

  it "reconstructs a native failed outcome from the selected failed evidence" do
    created = definition_events.first
    claim = claim_event
    failed = evidence_event(claim:, evidence_kind: "combined_tests", conclusion: "failed")
    selected = selection_event(event_payload(failed).evidence_id)
    terminal = outcome_event("failed")
    projector.call([ created, claim, failed, selected, terminal ])
    view = page(status: "failed").items.sole
    expect(view.outcome).to be_a(Coordinator::Read::VerificationObligationFailedViewV1)
    expect(view.outcome.triggering_evidence.event).to eq(event_reference(failed))
    expect(view.outcome.failed_at).to eq(timestamp(terminal))
    expect(view.progress.missing_evidence_kinds).to include("combined_tests")
  end

  it "does not derive progress from evidence rows and preserves explicit absolute facts on redelivery" do
    record = create(:coordinator_read_verification_obligation, obligation_id:, change_set_id:, evidence_count: 7)
    claim = claim_event
    submitted = evidence_event(claim:, evidence_kind: "combined_tests", conclusion: "passed")
    projector.call([ submitted, submitted ])
    expect(record.reload.evidence_count).to eq(7)
    expect(Coordinator::Read::VerificationObligationEvidenceItem.count).to eq(1)
    created_at = Coordinator::Read::VerificationObligationEvidenceItem.sole.created_at
    progress = progress_events(count: 1, passed: [ "combined_tests" ], missing: [])
    2.times { projector.call(progress) }
    expect(record.reload.evidence_count).to eq(1)
    expect(record.passed_evidence_kinds).to eq([ "combined_tests" ])
    projector.call([ submitted ])
    expect(record.reload.evidence_count).to eq(1)
    expect(Coordinator::Read::VerificationObligationEvidenceItem.sole.created_at).to eq(created_at)
  end

  it "serves a projected waiver while invalidation lags and then rebuilds its native lifecycle" do
    events = definition_events
    waived = append_obligation(
      Coordinator::Write::Events::VerificationObligationWaivedV2.new(
        obligation_id:, reason: { code: "accepted_risk", summary: "The user accepts the compatibility risk." }
      ),
      metadata: metadata("verification-obligation-waiver/v2", actor_kind: "user", actor_id: "project-owner").merge(
        policy: impact_policy(required_evidence: event_payload(events.first).required_evidence).to_h, waiver_input_digest: digest("a")
      ), caused_by: events.first
    )
    policy = impact_policy(required_evidence: %w[combined_tests contract_compatibility_review])
    invalidated = append_obligation(
      Coordinator::Write::Events::VerificationObligationInvalidatedV2.new(
        obligation_id:, superseding_partition_event: policy.partition_event.new(
          event_id: SecureRandom.uuid_v7, stream_revision: policy.partition_event.stream_revision + 1
        ), reason: "policy_partition_advanced"
      ),
      metadata: metadata("verification-obligation-validity/v1", actor_kind: "system",
        actor_id: "verification-obligation-validity-policy").merge(
          invalidated_policy: policy.to_h, invalidation_digest: digest("b"), rule_version: "verification-obligation-validity/v1"
        ), caused_by: waived
    )
    projector.call([ *events, waived ])
    expect(page(status: "waived").items.sole.outcome).to have_attributes(
      previous_status: "open", waived_at: timestamp(waived)
    )
    projector.call([ invalidated ])
    observed = page(status: "invalidated").items.sole
    expect(observed.outcome).to have_attributes(
      previous_status: "waived", previous_terminal_event: event_reference(waived),
      invalidated_at: timestamp(invalidated)
    )
    original = observed.to_h
    ReadModelTestSafety.clean!
    projector.call([ *events, waived, invalidated ])
    expect(page(status: "invalidated").items.sole.to_h).to eq(original)
  end

  it "replays creation and terminal facts without resetting independent progress or claims" do
    events = definition_events
    claim = claim_event
    waiver = append_obligation(
      Coordinator::Write::Events::VerificationObligationWaivedV2.new(
        obligation_id:, reason: { code: "accepted_risk", summary: "Accepted compatibility risk." }),
      metadata: metadata("verification-obligation-waiver/v2", actor_kind: "user", actor_id: "project-owner").merge(
        policy: impact_policy(required_evidence: %w[combined_tests contract_compatibility_review]).to_h, waiver_input_digest: digest("a")))
    projector.call([ *events, claim, *progress_events(count: 3, passed: [ "combined_tests" ], missing: [ "contract_compatibility_review" ]), waiver ])
    2.times { projector.call([ events.first, waiver ]) }
    record = Coordinator::Read::VerificationObligation.find(obligation_id)
    expect(record).to have_attributes(status: "waived", evidence_count: 3, claim_id: event_payload(claim).claim_id)
    expect(record.terminal_outcome.fetch("previous_status")).to eq("open")
    expect(Coordinator::Read::ProcessedProjectionEvent.count).to eq(0)
  end

  it "bulk patches a thousand absolute progress facts without counting evidence or loading unrelated state" do
    rows = Array.new(1000) { |index| attributes_for(:coordinator_read_verification_obligation, obligation_id: SecureRandom.uuid_v7, change_set_id: "CS-batch-#{index}") }
    Coordinator::Read::VerificationObligation.insert_all!(rows)
    events = rows.map.with_index do |row, index|
      ProjectionEventFactory.build(
        payload: Coordinator::Write::Events::ProjectionNumbers::VerificationObligationEvidenceNumberChangedV1.new(obligation_id: row.fetch(:obligation_id), evidence_number: 2),
        stream: streams.verification_obligation(row.fetch(:obligation_id)), stream_revision: 10, global_position: index + 2000,
        policy_version: "projection-numbers/v1")
    end
    statements = []
    ActiveSupport::Notifications.subscribed(->(*args) { statements << args.last.fetch(:sql) }, "sql.active_record") { projector.call(events) }
    expect(statements.count { _1.start_with?("UPDATE") }).to eq(1)
    expect(statements.grep(/SELECT.*verification_obligation/)).to be_empty
    expect(Coordinator::Read::VerificationObligation.where(evidence_count: 2).count).to eq(1000)
    projector.call(events)
    expect(Coordinator::Read::VerificationObligation.first.obligation).to eq(rows.first.fetch(:obligation))
    expect(Coordinator::Read::ProcessedProjectionEvent.count).to eq(0)
  end

  def progress_events(count:, passed:, missing:)
    [
      Coordinator::Write::Events::ProjectionNumbers::VerificationObligationEvidenceNumberChangedV1.new(obligation_id:, evidence_number: count),
      Coordinator::Write::Events::ProjectionNumbers::VerificationObligationEvidenceCoverageChangedV1.new(obligation_id:, passed_evidence_kinds: passed, missing_evidence_kinds: missing)
    ].map { append_obligation(_1, metadata: metadata("projection-numbers/v1")) }
  end

  def definition_events(complete: true)
    persist_candidate("source")
    persist_candidate("target")
    created = append_obligation(
      Coordinator::Write::Events::VerificationObligationCreatedV2.new(
        obligation_id:, kind: "candidate_compatibility", enforcement: "merge_gate",
        reasons: [ "changed_resource_overlap" ], required_evidence: %w[combined_tests contract_compatibility_review]
      ),
      metadata: metadata("candidate-compatibility-obligation/v1", actor_kind: "system",
        actor_id: "candidate-impact-obligation-policy", command_id: creation_command_id).merge(
          policy: impact_policy(required_evidence: %w[combined_tests contract_compatibility_review]).to_h,
          validity_input_digest: digest("1"), rule_version: "candidate-compatibility-obligation/v1"
        )
    )
    [ created, *(complete ? append_definition_assignments : []) ]
  end

  def append_definition_assignments
    [
      Coordinator::Write::Events::VerificationObligationAddedToChangeSetV1.new(obligation_id:, change_set_id:),
      Coordinator::Write::Events::VerificationObligationSourceCandidateAssignedV1.new(
        obligation_id:, candidate_id: "CAN-source"
      ),
      Coordinator::Write::Events::VerificationObligationTargetCandidateAssignedV1.new(
        obligation_id:, candidate_id: "CAN-target"
      )
    ].map do |fact|
      append_obligation(fact, metadata: metadata("candidate-compatibility-obligation/v1",
        actor_kind: "system", actor_id: "candidate-impact-obligation-policy", command_id: creation_command_id))
    end
  end

  def persist_candidate(role)
    candidate_id = "CAN-#{role}"
    manifest_digest = digest(role == "source" ? "c" : "d")
    candidate_stream = streams.candidate(candidate_id)
    facts = [
      Coordinator::Write::Events::CandidateCreatedV1.new(candidate_id:),
      Coordinator::Write::Events::CandidateAssignedToAttemptV1.new(
        candidate_id:, change_set_id:, work_item_id: "W-#{role}", attempt_id: "A-#{role}"
      ),
      Coordinator::Write::Events::CandidateAssignedToRepositoryV1.new(
        candidate_id:, repository_id: "018f0f4d-4e45-7abc-8def-000000000411"
      ),
      Coordinator::Write::Events::CandidateTargetBranchSelectedV1.new(candidate_id:, target_branch: "main"),
      Coordinator::Write::Events::CandidateCommitRangeDeclaredV1.new(
        candidate_id:, object_format: "sha1", base_commit_oid: "a" * 40,
        head_commit_oid: (role == "source" ? "b" : "e") * 40
      ),
      Coordinator::Write::Events::CandidateCheckpointKindSelectedV1.new(candidate_id:, checkpoint_kind: "final"),
      Coordinator::Write::Events::CandidateWorkIntentionSetAssignedV1.new(candidate_id:, intention_set_id: SecureRandom.uuid_v7),
      Coordinator::Write::Events::CandidateChangeManifestCapturedV2.new(
        candidate_id:, evidence_revision: 1, files: [
          { status: "modified", old_path: "app/models/invoice.rb", new_path: "app/models/invoice.rb",
            old_blob_oid: "c" * 40, new_blob_oid: "d" * 40, old_mode: "100644", new_mode: "100644" }
        ]
      ),
      Coordinator::Write::Events::CandidateSubmittedV3.new(candidate_id:)
    ]
    facts.each do |fact|
      envelope = metadata("candidate-submission/v1")
      if fact.is_a?(Coordinator::Write::Events::CandidateChangeManifestCapturedV2)
        envelope = envelope.merge(manifest_digest:,
          collector: { kind: "agent", id: "agent-blue", collector_version: "git-evidence-v1" })
      end
      append_source(candidate_stream, fact, metadata: envelope)
    end
    surface_id = SecureRandom.uuid_v7
    append_source(streams.candidate_impact_surface(surface_id),
      Coordinator::Write::Events::CandidateImpactSurfaceDerivedV2.new(
        surface_id:, candidate_id:, evidence_revision: 1, produces: [], consumes: [], may_affect: [], assumes: []
      ),
      metadata: metadata("candidate-impact-surface/v1").merge(
        analyzer: { kind: "agent", id: "agent-blue", analyzer_version: "fixture-v1" },
        manifest_digest:, build_context_digest: nil, surface_digest: digest(role == "source" ? "e" : "f")
      ))
    append_source(candidate_stream,
      Coordinator::Write::Events::CandidateImpactSurfaceAssignedV1.new(candidate_id:, surface_id:),
      metadata: metadata("candidate-impact-surface/v1"))
  end

  def claim_event(agent_id: "agent-blue", fencing_token: 1, expires_at: Time.now.utc + 300)
    append_obligation(
      Coordinator::Write::Events::VerificationObligationClaimedV2.new(
        obligation_id:, claim_id: SecureRandom.uuid_v7, claimant_id: agent_id,
        fencing_token:, expires_at: expires_at.utc.iso8601(6)
      ), metadata: metadata("verification-obligation-claim/v1", actor_id: agent_id)
    )
  end

  def evidence_event(claim:, evidence_kind:, conclusion:)
    claim_payload = event_payload(claim)
    input_digest = digest(evidence_kind == "combined_tests" ? "5" : "6")
    append_obligation(Coordinator::Write::Events::VerificationEvidenceSubmittedV2.new(
      obligation_id:, evidence_id: SecureRandom.uuid_v7, evidence_kind:,
      assessment: assessment(evidence_kind:, conclusion:, digest_character: "5"),
      claim: { claim_id: claim_payload.claim_id, claimant_id: claim_payload.claimant_id,
        fencing_token: claim_payload.fencing_token, claim_event: event_reference(claim) }
    ), metadata: metadata("compatibility-assessment/v2").merge(
      policy: impact_policy(required_evidence: %w[combined_tests contract_compatibility_review]).to_h,
      obligation_validity_input_digest: digest("1"), assessment_input_digest: input_digest
    ), caused_by: claim)
  end

  def selection_event(evidence_id)
    append_obligation(
      Coordinator::Write::Events::VerificationObligationEvidenceSelectedV1.new(obligation_id:, evidence_id:),
      metadata: metadata("verification-obligation-outcome/v2", actor_kind: "system", actor_id: "verification-evidence-outcome")
    )
  end

  def outcome_event(status)
    fact = if status == "satisfied"
      Coordinator::Write::Events::VerificationObligationSatisfiedV2.new(obligation_id:)
    else
      Coordinator::Write::Events::VerificationObligationFailedV2.new(obligation_id:, reason: nil)
    end
    append_obligation(fact, metadata: metadata("verification-obligation-outcome/v2",
      actor_kind: "system", actor_id: "verification-evidence-outcome").merge(
        outcome_digest: digest("8"), policy: impact_policy(required_evidence: %w[combined_tests contract_compatibility_review]).to_h
      ))
  end

  def metadata(policy_version, actor_kind: "agent", actor_id: "agent-blue", command_id: "cmd-native-verification")
    Coordinator::Write::EventMetadata.new(
      command_id:, actor_kind:, actor_id:, recorded_by: "coordinator", policy_version:
    ).to_h
  end

  def append_obligation(fact, metadata:, caused_by: nil)
    append_source(streams.verification_obligation(obligation_id), fact, metadata:, caused_by:)
  end

  def append_source(stream, fact, metadata:, caused_by: nil)
    metadata_class = case fact
    when Coordinator::Write::Events::VerificationObligationCreatedV2
      Coordinator::Write::Metadata::VerificationObligationV2
    when Coordinator::Write::Events::VerificationEvidenceSubmittedV2
      Coordinator::Write::Metadata::VerificationEvidenceV2
    when Coordinator::Write::Events::VerificationObligationSatisfiedV2,
         Coordinator::Write::Events::VerificationObligationFailedV2
      Coordinator::Write::Metadata::VerificationOutcomeV2
    when Coordinator::Write::Events::VerificationObligationWaivedV2
      Coordinator::Write::Metadata::VerificationWaiverV2
    when Coordinator::Write::Events::VerificationObligationInvalidatedV2
      Coordinator::Write::Metadata::VerificationInvalidationV2
    when Coordinator::Write::Events::CandidateChangeManifestCapturedV2
      Coordinator::Write::Metadata::CandidateChangeManifestV2
    when Coordinator::Write::Events::CandidateImpactSurfaceDerivedV2
      Coordinator::Write::Metadata::CandidateImpactSurfaceV2
    else
      Coordinator::Write::EventMetadata
    end
    event_store.append(stream, [
      event_factory.build!(event: fact, event_id: SecureRandom.uuid_v7,
        metadata: metadata_class.new(metadata), markers: [], caused_by:, correlation_id:)
    ]).sole
  end

  def source_loader
    Coordinator::Read::VerificationObligations::SourceLoader.new(event_store:)
  end

  def timestamp(event)
    event.created_at.utc.iso8601(6)
  end

  def event_payload(event)
    Coordinator::Write::EventSchemaRegistry.new.load(
      type: event.type, schema_version: event.metadata.fetch("schema_version"), data: event.data
    )
  end

  def assessment(evidence_kind:, conclusion:, digest_character:)
    Coordinator::Write::CompatibilityAssessments::AssessmentV1.new(
      evidence_kind:,
      producer: Coordinator::Write::CompatibilityAssessments::ProducerV1.new(
        name: "compatibility-tests",
        version: "1.0"
      ),
      run_id: "assessment-#{digest_character}",
      test_suite_digest: digest("2"),
      environment_digest: digest("3"),
      dependency_graph_digest: digest("4"),
      result_digest: digest(digest_character),
      conclusion:,
      findings: [],
      produced_at: "2026-08-30T12:02:00.000000Z"
    )
  end

  def impact_policy(required_evidence:)
    partition = Coordinator::Write::Decisions::DecisionPartitionV1.new(
      partition_id: "changeset:#{change_set_id}:candidate",
      topic_root: "candidate",
      anchor_kind: "changeset",
      anchor_id: change_set_id
    )
    partition_event = source_reference(
      "DecisionAddedToPartition", "DecisionPartition", partition.partition_id, 0, context: "HumanGuidance"
    )
    decision_event = source_reference(
      "DecisionActivated", "Decision", "D-obligation-policy", 1, context: "HumanGuidance"
    )
    Coordinator::Write::CandidateObligations::ImpactPolicyEvidenceV1.new(
      partition_event:,
      partition:,
      head: Coordinator::Write::Decisions::DecisionHeadV1.new(
        decision_id: "D-obligation-policy",
        decision_revision: 1,
        event: decision_event
      ),
      definition_digest: digest("0"),
      change_set_id:,
      required_evidence:,
      enforcement: "merge_gate",
      valid_from: "2026-08-30T11:59:00.000000Z"
    )
  end

  def source_reference(type, stream_name, stream_id, revision, context: "DevelopmentIntegration")
    Coordinator::Write::EventReference.new(
      event_id: SecureRandom.uuid_v7,
      type:,
      stream_context: context,
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

  def page(status: "open", observed_at: "2026-08-30T12:00:00.000000Z")
    repository.page(
      Coordinator::Read::VerificationObligationListQueryV1.new(
        obligation_id: nil,
        change_set_id:,
        candidate_id: nil,
        work_item_id: nil,
        repository_id: nil,
        kind: nil,
        enforcement: nil,
        status:,
        claimant_id: nil,
        claim_state: nil,
        after_global_position: nil,
        limit: 20,
        observed_at:
      )
    )
  end

  def digest(character)
    "sha256:#{character * 64}"
  end
end
