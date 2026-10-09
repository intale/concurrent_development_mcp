# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::VerificationObligationsV1, :read_model do
  subject(:projector) { described_class.new }

  let(:repository) { Coordinator::Read::Repositories::VerificationObligations.new }
  let(:obligation_id) { SecureRandom.uuid_v7 }
  let(:creation_command_id) { SecureRandom.uuid_v7 }
  let(:change_set_id) { "CS-obligation-projection" }
  let(:correlation_id) { SecureRandom.uuid_v7 }

  it "projects complete creation evidence idempotently and rebuilds without write-side effects" do
    created = creation_event
    payload = event_payload(created)

    projector.call(created)
    projector.call(created)

    first = page.items.sole
    expect(Coordinator::Read::VerificationObligation.count).to eq(1)
    expect(first).to have_attributes(
      obligation_id:,
      kind: "candidate_compatibility",
      status: "open",
      enforcement: "merge_gate",
      source_candidate: payload.source_candidate,
      target_candidate: payload.target_candidate,
      reasons: payload.reasons,
      required_evidence: payload.required_evidence,
      policy: payload.policy,
      validity_input_digest: payload.validity_input_digest,
      claim_state: "unclaimed",
      claim: nil
    )
    expect(first.evidence).to have_attributes(
      event: event_reference(created),
      actor: have_attributes(kind: "system", id: "candidate-impact-obligation-policy", authenticated: false),
      markers: created.markers,
      metadata: created.metadata,
      global_position: created.global_position,
      causation_id: created.causation_id,
      correlation_id: created.correlation_id
    )

    original = first.to_h
    ReadModelTestSafety.clean!
    projector.call(created)

    expect(page.items.sole.to_h).to eq(original)
  end

  it "projects the latest fenced claim without changing the open obligation or its creation cursor" do
    created = creation_event
    first_claim = claim_event(
      created:,
      agent_id: "agent-blue",
      fencing_token: 1,
      revision: 1,
      position: 200,
      claimed_at: "2026-08-30T12:00:00.000000Z",
      expires_at: "2026-08-30T12:05:00.000000Z"
    )
    projector.call(created)
    projector.call(first_claim)
    projector.call(first_claim)

    active = page(observed_at: "2026-08-30T12:04:59.999999Z").items.sole
    expect(active).to have_attributes(status: "open", claim_state: "active")
    expect(active.claim).to have_attributes(
      claim_id: event_payload(first_claim).claim_id,
      claimant_id: "agent-blue",
      fencing_token: 1,
      claimed_at: "2026-08-30T12:00:00.000000Z",
      expires_at: "2026-08-30T12:05:00.000000Z"
    )
    expect(active.evidence.global_position).to eq(created.global_position)
    expect(active.claim.evidence).to have_attributes(
      event: event_reference(first_claim),
      actor: have_attributes(kind: "agent", id: "agent-blue", authenticated: false),
      global_position: first_claim.global_position,
      causation_id: first_claim.causation_id,
      correlation_id: first_claim.correlation_id
    )

    second_claim = claim_event(
      created:,
      agent_id: "agent-green",
      fencing_token: 2,
      revision: 2,
      position: 300,
      claimed_at: "2026-08-30T12:05:00.000000Z",
      expires_at: "2026-08-30T12:10:00.000000Z"
    )
    projector.call(second_claim)

    reclaimed = page(observed_at: "2026-08-30T12:05:00.000000Z").items.sole
    expect(reclaimed).to have_attributes(status: "open", claim_state: "active")
    expect(reclaimed.claim).to have_attributes(
      claim_id: event_payload(second_claim).claim_id,
      claimant_id: "agent-green",
      fencing_token: 2
    )
    expect(Coordinator::Read::VerificationObligation.count).to eq(1)
  end

  it "rolls back an out-of-order claim and accepts it after its creation fact" do
    created = creation_event
    claim = claim_event(
      created:,
      agent_id: "agent-blue",
      fencing_token: 1,
      revision: 1,
      position: 200,
      claimed_at: "2026-08-30T12:00:00.000000Z",
      expires_at: "2026-08-30T12:05:00.000000Z"
    )

    expect { projector.call(claim) }
      .to raise_error(Coordinator::Read::InvalidProjectionSource, /cannot precede VerificationObligationCreated/)
    expect(Coordinator::Read::ProcessedProjectionEvent.where(event_id: claim.id)).not_to exist

    projector.call(created)
    projector.call(claim)

    expect(page(observed_at: "2026-08-30T12:00:01.000000Z").items.sole.claim).to have_attributes(
      claimant_id: "agent-blue",
      fencing_token: 1
    )
  end

  it "projects ordered normalized evidence, progress, satisfaction, and a complete rebuild" do
    created = creation_event
    claim = default_claim(created)
    first = evidence_event(
      created:,
      claim:,
      evidence_kind: "combined_tests",
      conclusion: "passed",
      revision: 2,
      position: 300,
      id_suffix: "501"
    )
    second = evidence_event(
      created:,
      claim:,
      evidence_kind: "contract_compatibility_review",
      conclusion: "passed",
      revision: 3,
      position: 400,
      id_suffix: "502"
    )
    satisfied = satisfaction_event(created:, evidence: [ first, second ], revision: 4, position: 500)

    [ created, claim, first ].each { projector.call(_1) }
    projector.call(first)
    partial = page(observed_at: "2026-08-30T12:02:00.000000Z").items.sole
    expect(partial).to have_attributes(status: "open", outcome: nil)
    expect(partial.progress).to have_attributes(
      required_evidence_kinds: %w[combined_tests contract_compatibility_review],
      passed_evidence_kinds: [ "combined_tests" ],
      missing_evidence_kinds: [ "contract_compatibility_review" ],
      evidence_count: 1
    )
    expect(partial.submitted_evidence.sole).to have_attributes(
      evidence_id: event_payload(first).evidence_id,
      evidence_kind: "combined_tests",
      assessment_input_digest: event_payload(first).assessment_input_digest,
      assessment: have_attributes(conclusion: "passed")
    )
    expect(partial.submitted_evidence.sole.evidence.event.event_id).to eq(first.id)
    expect(event_payload(first).evidence_id).not_to eq(first.id)

    [ second, satisfied ].each do |event|
      projector.call(event)
      projector.call(event)
    end
    observed = page(status: "satisfied", observed_at: "2026-08-30T12:04:00.000000Z").items.sole
    expect(observed.evidence.global_position).to eq(created.global_position)
    expect(observed.progress).to have_attributes(
      passed_evidence_kinds: %w[combined_tests contract_compatibility_review],
      missing_evidence_kinds: [],
      evidence_count: 2
    )
    expect(observed.submitted_evidence.map(&:evidence_kind)).to eq(
      %w[combined_tests contract_compatibility_review]
    )
    expect(observed.outcome).to be_a(Coordinator::Read::VerificationObligationSatisfiedViewV1)
    expect(observed.outcome).to have_attributes(
      selected_evidence: event_payload(satisfied).selected_evidence,
      outcome_digest: event_payload(satisfied).outcome_digest,
      satisfied_at: event_payload(satisfied).satisfied_at
    )
    expect(observed.outcome.evidence).to have_attributes(
      event: event_reference(satisfied),
      causation_id: satisfied.causation_id,
      correlation_id: satisfied.correlation_id
    )
    expect(Coordinator::Read::VerificationObligationEvidenceItem.count).to eq(2)

    original = observed.to_h
    ReadModelTestSafety.clean!
    [ created, claim, first, second, satisfied ].each { projector.call(_1) }
    expect(page(status: "satisfied", observed_at: "2026-08-30T12:04:00.000000Z").items.sole.to_h).to eq(original)
  end

  it "rolls back evidence and terminal facts until their projected predecessors arrive" do
    created = creation_event(required_evidence: [ "combined_tests" ])
    claim = default_claim(created)
    evidence = evidence_event(
      created:,
      claim:,
      evidence_kind: "combined_tests",
      conclusion: "failed",
      revision: 2,
      position: 300,
      id_suffix: "503"
    )
    failure = failure_event(created:, evidence:, revision: 3, position: 400)

    projector.call(created)
    expect { projector.call(evidence) }
      .to raise_error(Coordinator::Read::InvalidProjectionSource, /VerificationObligationClaimed/)
    expect(Coordinator::Read::ProcessedProjectionEvent.where(event_id: evidence.id)).not_to exist

    projector.call(claim)
    expect { projector.call(failure) }
      .to raise_error(Coordinator::Read::InvalidProjectionSource, /projected evidence/)
    expect(Coordinator::Read::ProcessedProjectionEvent.where(event_id: failure.id)).not_to exist

    projector.call(evidence)
    projector.call(failure)
    failed = page(status: "failed", observed_at: "2026-08-30T12:03:00.000000Z").items.sole
    expect(failed).to have_attributes(status: "failed")
    expect(failed.progress).to have_attributes(
      passed_evidence_kinds: [],
      missing_evidence_kinds: [ "combined_tests" ],
      evidence_count: 1
    )
    expect(failed.outcome).to be_a(Coordinator::Read::VerificationObligationFailedViewV1)
    expect(failed.outcome.triggering_evidence).to eq(event_payload(failure).triggering_evidence)
  end

  it "projects a user waiver and a later policy invalidation without a freshness gate" do
    created = creation_event
    waived = waiver_event(created:, revision: 1, position: 200)
    invalidated = invalidation_event(created:, waived:, revision: 2, position: 300)
    projector.call(created)
    projector.call(waived)

    waived_view = page(status: "waived").items.sole
    expect(waived_view.outcome).to be_a(Coordinator::Read::VerificationObligationWaivedViewV1)
    expect(waived_view.outcome).to have_attributes(
      previous_status: "open",
      reason: have_attributes(code: "accepted_risk")
    )

    projector.call(invalidated)
    invalidated_view = page(status: "invalidated").items.sole
    expect(invalidated_view.outcome).to be_a(Coordinator::Read::VerificationObligationInvalidatedViewV1)
    expect(invalidated_view.outcome).to have_attributes(
      previous_status: "waived",
      superseding_partition_event: event_payload(invalidated).superseding_partition_event
    )

    original = invalidated_view.to_h
    ReadModelTestSafety.clean!
    [ created, waived, invalidated ].each { projector.call(_1) }
    expect(page(status: "invalidated").items.sole.to_h).to eq(original)
  end

  def creation_event(required_evidence: %w[combined_tests contract_compatibility_review])
    policy = impact_policy(required_evidence:)
    payload = Coordinator::Write::Events::VerificationObligationCreatedV1.new(
      obligation_id:,
      kind: "candidate_compatibility",
      status: "open",
      change_set_id:,
      source_candidate: candidate_subject("source", "411", "b"),
      target_candidate: candidate_subject("target", "412", "e"),
      reasons: [
        Coordinator::Write::CandidateObligations::ImpactReasonV1.new(
          kind: "changed_resource_overlap",
          matches: [ "app/models/invoice.rb" ],
          source_evidence: source_reference("CandidateImpactSurfaceDerived", "Candidate", "CAN-source", 2),
          target_evidence: source_reference("CandidateImpactSurfaceDerived", "Candidate", "CAN-target", 2)
        )
      ],
      required_evidence:,
      enforcement: "merge_gate",
      policy:,
      validity_input_digest: digest("1"),
      rule_version: "candidate-compatibility-obligation/v1",
      created_at: "2026-08-30T12:00:00.000000Z"
    )
    obligation_event(
      payload,
      revision: 0,
      position: 100,
      policy_version: "candidate-compatibility-obligation/v1",
      command_id: creation_command_id,
      actor_kind: "system",
      actor_id: "candidate-impact-obligation-policy"
    )
  end

  def default_claim(created)
    claim_event(
      created:,
      agent_id: "agent-blue",
      fencing_token: 1,
      revision: 1,
      position: 200,
      claimed_at: "2026-08-30T12:01:00.000000Z",
      expires_at: "2026-08-30T12:06:00.000000Z"
    )
  end

  def claim_event(created:, agent_id:, fencing_token:, revision:, position:, claimed_at:, expires_at:)
    obligation_event(
      Coordinator::Write::Events::VerificationObligationClaimedV1.new(
        obligation_id:,
        obligation_event: event_reference(created),
        claim_id: SecureRandom.uuid_v7,
        claimant_id: agent_id,
        fencing_token:,
        claimed_at:,
        expires_at:
      ),
      revision:,
      position:,
      policy_version: "verification-obligation-claim/v1",
      command_id: "cmd-claim-#{agent_id}-#{fencing_token}",
      actor_id: agent_id,
      causation_id: created.id
    )
  end

  def evidence_event(created:, claim:, evidence_kind:, conclusion:, revision:, position:, id_suffix:)
    claim_payload = event_payload(claim)
    payload = Coordinator::Write::Events::VerificationEvidenceSubmittedV1.new(
      obligation_id:,
      obligation_event: event_reference(created),
      evidence_id: "018f0f4d-4e45-7abc-8def-000000000#{id_suffix}",
      evidence_kind:,
      claim: Coordinator::Write::CompatibilityAssessments::ClaimEvidenceV1.new(
        claim_id: claim_payload.claim_id,
        claimant_id: claim_payload.claimant_id,
        fencing_token: claim_payload.fencing_token,
        claim_event: event_reference(claim)
      ),
      source_candidate: event_payload(created).source_candidate,
      target_candidate: event_payload(created).target_candidate,
      policy: event_payload(created).policy,
      obligation_validity_input_digest: event_payload(created).validity_input_digest,
      assessment: assessment(evidence_kind:, conclusion:, digest_character: id_suffix[-1]),
      assessment_input_digest: digest(id_suffix[-1]),
      submitted_at: "2026-08-30T12:0#{revision}:00.000000Z"
    )
    obligation_event(
      payload,
      revision:,
      position:,
      policy_version: "compatibility-assessment/v1",
      command_id: "cmd-evidence-#{id_suffix}",
      actor_id: claim_payload.claimant_id,
      causation_id: claim.id
    )
  end

  def satisfaction_event(created:, evidence:, revision:, position:)
    obligation_event(
      Coordinator::Write::Events::VerificationObligationSatisfiedV1.new(
        obligation_id:,
        obligation_event: event_reference(created),
        policy: event_payload(created).policy,
        selected_evidence: evidence.map { decision_reference(_1) },
        outcome_digest: digest("8"),
        satisfied_at: "2026-08-30T12:04:00.000000Z"
      ),
      revision:,
      position:,
      policy_version: "compatibility-assessment/v1",
      command_id: "cmd-satisfy-obligation",
      actor_id: "agent-blue",
      causation_id: evidence.last.id
    )
  end

  def failure_event(created:, evidence:, revision:, position:)
    obligation_event(
      Coordinator::Write::Events::VerificationObligationFailedV1.new(
        obligation_id:,
        obligation_event: event_reference(created),
        policy: event_payload(created).policy,
        triggering_evidence: decision_reference(evidence),
        outcome_digest: digest("9"),
        failed_at: "2026-08-30T12:03:00.000000Z"
      ),
      revision:,
      position:,
      policy_version: "compatibility-assessment/v1",
      command_id: "cmd-fail-obligation",
      actor_id: "agent-blue",
      causation_id: evidence.id
    )
  end

  def waiver_event(created:, revision:, position:)
    obligation_event(
      Coordinator::Write::Events::VerificationObligationWaivedV1.new(
        obligation_id:,
        obligation_event: event_reference(created),
        policy: event_payload(created).policy,
        previous_status: "open",
        previous_terminal_event: nil,
        reason: Coordinator::Write::VerificationObligationWaivers::ReasonV1.new(
          code: "accepted_risk",
          summary: "The user accepts the compatibility risk."
        ),
        waiver_input_digest: digest("a"),
        waived_at: "2026-08-30T12:01:00.000000Z"
      ),
      revision:,
      position:,
      policy_version: "verification-obligation-waiver/v1",
      command_id: "cmd-waive-obligation",
      actor_kind: "user",
      actor_id: "project-owner",
      causation_id: created.id
    )
  end

  def invalidation_event(created:, waived:, revision:, position:)
    policy = event_payload(created).policy
    superseding = policy.partition_event.new(
      event_id: SecureRandom.uuid_v7,
      stream_revision: policy.partition_event.stream_revision + 1
    )
    obligation_event(
      Coordinator::Write::Events::VerificationObligationInvalidatedV1.new(
        obligation_id:,
        obligation_event: event_reference(created),
        invalidated_policy: policy,
        superseding_partition_event: superseding,
        previous_status: "waived",
        previous_terminal_event: event_reference(waived),
        reason: "policy_partition_advanced",
        invalidation_digest: digest("b"),
        rule_version: "verification-obligation-validity/v1",
        invalidated_at: "2026-08-30T12:02:00.000000Z"
      ),
      revision:,
      position:,
      policy_version: "verification-obligation-validity/v1",
      command_id: "cmd-invalidate-obligation",
      actor_kind: "system",
      actor_id: "verification-obligation-validity-policy",
      causation_id: waived.id
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

  def decision_reference(evidence)
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

  def candidate_subject(role, repository_suffix, head_character)
    candidate_id = "CAN-#{role}"
    Coordinator::Write::CandidateObligations::CandidateSubjectV1.new(
      candidate_id:,
      change_set_id:,
      work_item_id: "WI-#{role}",
      attempt_id: "ATT-#{role}",
      repository_id: "018f0f4d-4e45-7abc-8def-000000000#{repository_suffix}",
      target_branch: "main",
      object_format: "sha1",
      base_commit_oid: "a" * 40,
      head_commit_oid: head_character * 40,
      manifest_digest: digest(role == "source" ? "c" : "d"),
      build_context_digest: nil,
      surface_digest: digest(role == "source" ? "e" : "f"),
      candidate_event: source_reference("CandidateSubmitted", "Candidate", candidate_id, 0),
      manifest_event: source_reference("CandidateChangeManifestCaptured", "Candidate", candidate_id, 1),
      build_context_event: nil,
      surface_event: source_reference("CandidateImpactSurfaceDerived", "Candidate", candidate_id, 2),
      registration_event: source_reference("CandidateImpactSurfaceRegistered", "CandidateImpactRegistry", change_set_id, role == "source" ? 0 : 1)
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

  def obligation_event(
    payload,
    revision:,
    position:,
    policy_version:,
    command_id:,
    actor_kind: "agent",
    actor_id: "agent-blue",
    causation_id: nil
  )
    ProjectionEventFactory.build(
      payload:,
      stream: Coordinator::Write::StreamFactory.new.verification_obligation(obligation_id),
      stream_revision: revision,
      global_position: position,
      policy_version:,
      command_id:,
      actor_kind:,
      actor_id:,
      markers: [ "verification-obligation:#{obligation_id}" ],
      correlation_id:,
      causation_id:
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

  def event_payload(event)
    Coordinator::Write::EventSchemaRegistry.new.load(
      type: event.type,
      schema_version: event.metadata.fetch("schema_version"),
      data: event.data
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
