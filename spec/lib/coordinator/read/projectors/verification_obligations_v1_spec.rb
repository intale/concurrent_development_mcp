# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::VerificationObligationsV1,
               :event_store,
               :read_model do
  let(:projector) { described_class.new }
  let(:repository) { Coordinator::Read::Repositories::VerificationObligations.new }
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }

  it "projects complete creation evidence idempotently and rebuilds without write-side effects" do
    created = CandidateObligationScenario.create_obligation(prefix: "obligation-projection")
    event = created.fetch(:event)
    payload = created.fetch(:payload)

    projector.call(event)
    projector.call(event)

    first = page(change_set_id: created.dig(:pair, :ids, :change_set_id)).items.sole
    expect(Coordinator::Read::VerificationObligation.count).to eq(1)
    expect(first).to have_attributes(
      obligation_id: payload.obligation_id,
      kind: "candidate_compatibility",
      status: "open",
      enforcement: "merge_gate",
      source_candidate: payload.source_candidate,
      target_candidate: payload.target_candidate,
      reasons: payload.reasons,
      required_evidence: payload.required_evidence,
      policy: payload.policy,
      validity_input_digest: payload.validity_input_digest
    )
    expect(first).to have_attributes(claim_state: "unclaimed", claim: nil)
    expect(first.evidence).to have_attributes(
      event: CandidateObligationScenario.reference(event),
      actor: have_attributes(
        kind: "system",
        id: "candidate-impact-obligation-policy",
        authenticated: false
      ),
      markers: event.markers,
      metadata: event.metadata,
      global_position: event.global_position,
      causation_id: event.causation_id,
      correlation_id: event.correlation_id
    )

    original = first.to_h
    ReadModelTestSafety.clean!
    projector.call(event)

    expect(page(change_set_id: payload.change_set_id).items.sole.to_h).to eq(original)
    expect(CandidateObligationScenario.obligation_events(payload.obligation_id)).to contain_exactly(event)
  end

  it "projects the latest fenced claim without changing the open obligation or its creation cursor" do
    created = CandidateObligationScenario.create_obligation(prefix: "obligation-claim-projection")
    obligation_id = created.fetch(:result).obligation_id
    projector.call(created.fetch(:event))

    first_claim = claim(
      obligation_id:,
      command_id: "cmd-project-claim-blue",
      agent_id: "agent-blue",
      at: Time.utc(2026, 8, 24, 7, 0, 0)
    )
    projector.call(first_claim)
    projector.call(first_claim)

    active = page(
      change_set_id: created.dig(:pair, :ids, :change_set_id),
      observed_at: "2026-08-24T07:04:59.999999Z"
    ).items.sole
    expect(active).to have_attributes(
      status: "open",
      claim_state: "active",
      claim: have_attributes(
        claim_id: first_claim.data.fetch("claim_id"),
        claimant_id: "agent-blue",
        fencing_token: 1,
        claimed_at: "2026-08-24T07:00:00.000000Z",
        expires_at: "2026-08-24T07:05:00.000000Z"
      )
    )
    expect(active.evidence.global_position).to eq(created.fetch(:event).global_position)
    expect(active.claim.evidence).to have_attributes(
      event: CandidateObligationScenario.reference(first_claim),
      actor: have_attributes(kind: "agent", id: "agent-blue", authenticated: false),
      markers: first_claim.markers,
      metadata: first_claim.metadata,
      global_position: first_claim.global_position,
      causation_id: first_claim.causation_id,
      correlation_id: first_claim.correlation_id
    )

    second_claim = claim(
      obligation_id:,
      command_id: "cmd-project-claim-green",
      agent_id: "agent-green",
      at: Time.utc(2026, 8, 24, 7, 5, 0)
    )
    projector.call(second_claim)

    reclaimed = page(
      change_set_id: created.dig(:pair, :ids, :change_set_id),
      observed_at: "2026-08-24T07:05:00.000000Z"
    ).items.sole
    expect(reclaimed).to have_attributes(status: "open", claim_state: "active")
    expect(reclaimed.claim).to have_attributes(
      claim_id: second_claim.data.fetch("claim_id"),
      claimant_id: "agent-green",
      fencing_token: 2
    )
    expect(Coordinator::Read::VerificationObligation.count).to eq(1)
  end

  it "rolls back an out-of-order claim and accepts it after its creation fact" do
    created = CandidateObligationScenario.create_obligation(prefix: "obligation-claim-order")
    obligation_id = created.fetch(:result).obligation_id
    claim_event = claim(
      obligation_id:,
      command_id: "cmd-project-claim-order",
      agent_id: "agent-blue",
      at: Time.utc(2026, 8, 24, 7, 0, 0)
    )

    expect { projector.call(claim_event) }
      .to raise_error(
        Coordinator::Read::InvalidProjectionSource,
        /cannot precede VerificationObligationCreated/
      )
    expect(Coordinator::Read::ProcessedProjectionEvent.where(event_id: claim_event.id)).not_to exist

    projector.call(created.fetch(:event))
    projector.call(claim_event)

    projected = page(
      change_set_id: created.dig(:pair, :ids, :change_set_id),
      observed_at: "2026-08-24T07:00:01.000000Z"
    ).items.sole
    expect(projected.claim).to have_attributes(claimant_id: "agent-blue", fencing_token: 1)
  end

  it "projects ordered normalized evidence, progress, satisfaction, and a complete rebuild" do
    created = CandidateObligationScenario.create_obligation(prefix: "obligation-evidence-projection")
    obligation_id = created.fetch(:result).obligation_id
    projector.call(created.fetch(:event))
    claim_data = CandidateObligationScenario.claim_obligation(
      created:,
      prefix: "obligation-evidence-projection"
    )
    claim_event = history(obligation_id).find { _1.type == "VerificationObligationClaimed" }
    projector.call(claim_event)

    first = CandidateObligationScenario.submit_compatibility_assessment(
      created:,
      claim: claim_data,
      command_id: "cmd-project-combined-tests"
    )
    first_event = history(obligation_id).find do |event|
      event.type == "VerificationEvidenceSubmitted" && event.data.fetch("evidence_id") == first.evidence_id
    end
    projector.call(first_event)
    projector.call(first_event)

    partial = page(
      change_set_id: created.dig(:pair, :ids, :change_set_id),
      observed_at: first.submitted_at
    ).items.sole
    expect(partial).to have_attributes(status: "open", outcome: nil)
    expect(partial.progress).to have_attributes(
      required_evidence_kinds: %w[combined_tests contract_compatibility_review],
      passed_evidence_kinds: [ "combined_tests" ],
      missing_evidence_kinds: [ "contract_compatibility_review" ],
      evidence_count: 1
    )
    expect(partial.submitted_evidence.sole).to have_attributes(
      evidence_id: first.evidence_id,
      evidence_kind: "combined_tests",
      assessment_input_digest: first.assessment_input_digest,
      assessment: have_attributes(conclusion: "passed")
    )
    expect(partial.submitted_evidence.sole.evidence.event.event_id).to eq(first_event.id)
    expect(first.evidence_id).not_to eq(first_event.id)

    final = CandidateObligationScenario.submit_compatibility_assessment(
      created:,
      claim: claim_data,
      command_id: "cmd-project-contract-review",
      evidence_kind: "contract_compatibility_review"
    )
    final_events = history(obligation_id).select { _1.stream_revision > first_event.stream_revision }
    outcome_payload = CandidateObligationScenario.load(
      final_events.find { _1.type == "VerificationObligationSatisfied" }
    )
    final_events.each do |event|
      projector.call(event)
      projector.call(event)
    end

    satisfied = page(
      change_set_id: created.dig(:pair, :ids, :change_set_id),
      status: "satisfied",
      observed_at: final.submitted_at
    ).items.sole
    expect(satisfied.evidence.global_position).to eq(created.fetch(:event).global_position)
    expect(satisfied.progress).to have_attributes(
      passed_evidence_kinds: %w[combined_tests contract_compatibility_review],
      missing_evidence_kinds: [],
      evidence_count: 2
    )
    expect(satisfied.submitted_evidence.map(&:evidence_kind)).to eq(
      %w[combined_tests contract_compatibility_review]
    )
    expect(satisfied.outcome).to be_a(Coordinator::Read::VerificationObligationSatisfiedViewV1)
    expect(satisfied.outcome).to have_attributes(
      selected_evidence: outcome_payload.selected_evidence,
      outcome_digest: outcome_payload.outcome_digest,
      satisfied_at: outcome_payload.satisfied_at
    )
    expect(satisfied.outcome.evidence).to have_attributes(
      event: final.outcome_event,
      causation_id: final_events.last.causation_id,
      correlation_id: final_events.last.correlation_id
    )
    expect(Coordinator::Read::VerificationObligationEvidenceItem.count).to eq(2)

    original = satisfied.to_h
    complete_history = history(obligation_id)
    ReadModelTestSafety.clean!
    complete_history.each { projector.call(_1) }

    expect(
      page(
        change_set_id: created.dig(:pair, :ids, :change_set_id),
        status: "satisfied",
        observed_at: final.submitted_at
      ).items.sole.to_h
    ).to eq(original)
    expect(Coordinator::Read::VerificationObligationEvidenceItem.count).to eq(2)
  end

  it "rolls back evidence and terminal facts until their projected predecessors arrive" do
    created = CandidateObligationScenario.create_obligation(
      prefix: "obligation-failure-order",
      required_evidence: [ "combined_tests" ]
    )
    obligation_id = created.fetch(:result).obligation_id
    claim_data = CandidateObligationScenario.claim_obligation(
      created:,
      prefix: "obligation-failure-order"
    )
    receipt = CandidateObligationScenario.submit_compatibility_assessment(
      created:,
      claim: claim_data,
      command_id: "cmd-project-failed-tests",
      conclusion: "failed"
    )
    events = history(obligation_id)
    claim_event = events.find { _1.type == "VerificationObligationClaimed" }
    evidence_event = events.find { _1.type == "VerificationEvidenceSubmitted" }
    failure_event = events.find { _1.type == "VerificationObligationFailed" }

    projector.call(created.fetch(:event))
    expect { projector.call(evidence_event) }
      .to raise_error(Coordinator::Read::InvalidProjectionSource, /VerificationObligationClaimed/)
    expect(Coordinator::Read::ProcessedProjectionEvent.where(event_id: evidence_event.id)).not_to exist

    projector.call(claim_event)
    expect { projector.call(failure_event) }
      .to raise_error(Coordinator::Read::InvalidProjectionSource, /projected evidence/)
    expect(Coordinator::Read::ProcessedProjectionEvent.where(event_id: failure_event.id)).not_to exist

    projector.call(evidence_event)
    projector.call(failure_event)
    failed = page(
      change_set_id: created.dig(:pair, :ids, :change_set_id),
      status: "failed",
      observed_at: receipt.submitted_at
    ).items.sole
    expect(failed).to have_attributes(status: "failed")
    expect(failed.progress).to have_attributes(
      passed_evidence_kinds: [],
      missing_evidence_kinds: [ "combined_tests" ],
      evidence_count: 1
    )
    expect(failed.outcome).to be_a(Coordinator::Read::VerificationObligationFailedViewV1)
    expect(failed.outcome.triggering_evidence).to eq(CandidateObligationScenario.load(failure_event).triggering_evidence)
  end

  it "projects a user waiver and a later policy invalidation without a freshness gate" do
    created = CandidateObligationScenario.create_obligation(prefix: "obligation-lifecycle-projection")
    obligation_id = created.fetch(:payload).obligation_id
    Coordinator::Write::Operations::ExecuteWaiveVerificationObligation.new(event_store:).call(
      CandidateObligationScenario.waiver_arguments(
        created:,
        command_id: "cmd-project-obligation-waiver"
      )
    ).value!
    corrected = CandidateObligationScenario.correct_policy(
      policy: created.fetch(:policy),
      prefix: "obligation-lifecycle-projection",
      change_set_id: created.dig(:pair, :ids, :change_set_id)
    )
    source = corrected.fetch(:partition_event)
    invocation = Coordinator::Processes::VerificationObligationValidity::CommandBuilder.new.invalidation(
      obligation_event: created.fetch(:event),
      superseding_partition_event: CandidateObligationScenario.reference(source),
      caused_by_event: source,
      caused_by_reference: CandidateObligationScenario.reference(source)
    )
    Coordinator::Write::Operations::ExecuteInvalidateVerificationObligation.new(event_store:)
      .call(invocation).value!
    lifecycle = history(obligation_id)

    projector.call(created.fetch(:event))
    projector.call(lifecycle.find { _1.type == "VerificationObligationWaived" })
    waived = page(
      change_set_id: created.dig(:pair, :ids, :change_set_id),
      status: "waived"
    ).items.sole
    expect(waived.outcome).to be_a(Coordinator::Read::VerificationObligationWaivedViewV1)
    expect(waived.outcome).to have_attributes(
      previous_status: "open",
      reason: have_attributes(code: "accepted_risk")
    )

    projector.call(lifecycle.find { _1.type == "VerificationObligationInvalidated" })
    invalidated = page(
      change_set_id: created.dig(:pair, :ids, :change_set_id),
      status: "invalidated"
    ).items.sole
    expect(invalidated.outcome).to be_a(Coordinator::Read::VerificationObligationInvalidatedViewV1)
    expect(invalidated.outcome).to have_attributes(
      previous_status: "waived",
      superseding_partition_event: CandidateObligationScenario.reference(source)
    )

    original = invalidated.to_h
    ReadModelTestSafety.clean!
    lifecycle.each { projector.call(_1) }
    expect(
      page(
        change_set_id: created.dig(:pair, :ids, :change_set_id),
        status: "invalidated"
      ).items.sole.to_h
    ).to eq(original)
  end

  private

  def page(change_set_id:, status: "open", observed_at: "2026-08-24T07:00:00.000000Z")
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

  def claim(obligation_id:, command_id:, agent_id:, at:)
    Timecop.freeze(at) do
      Coordinator::Write::Operations::ExecuteClaimVerificationObligation.new(event_store:).call(
        command_id:,
        actor: { kind: "agent", id: agent_id },
        obligation_id:,
        claim_duration_seconds: 300
      ).value!
    end
    claim_events(obligation_id).last
  end

  def claim_events(obligation_id)
    event_store.read(
      streams.verification_obligation(obligation_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "VerificationObligationClaimed" ],
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def history(obligation_id)
    CandidateObligationScenario.verification_history(obligation_id)
  end
end
