# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::VerificationObligationsList,
               :event_store,
               :read_model do
  subject(:query) { described_class.new }

  let(:projector) { Coordinator::Read::Projectors::VerificationObligationsV1.new }
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }

  it "serves lagging empty pages and cursor-pages obligations through ANDed filters" do
    first = CandidateObligationScenario.create_obligation(prefix: "obligation-query")
    change_set_id = first.dig(:pair, :ids, :change_set_id)

    lagging = query.call(change_set_id:).value!
    expect(lagging).to have_attributes(status: "ok")
    expect(lagging.data.page).to have_attributes(items: [], has_more: false)

    projector.call(first.fetch(:event))
    corrected = CandidateObligationScenario.correct_policy(
      policy: first.fetch(:policy),
      prefix: "obligation-query",
      change_set_id:,
      level: "verification_gate"
    )
    second_result = CandidateObligationScenario.execute(
      Coordinator::Write::Operations::ExecuteCreateCandidateCompatibilityObligation,
      CandidateObligationScenario.invocation(
        pair: first.fetch(:pair),
        policy: corrected,
        caused_by: corrected.fetch(:partition_event)
      )
    )
    second_event = CandidateObligationScenario.obligation_events(second_result.obligation_id).sole
    projector.call(second_event)

    first_page = query.call(change_set_id:, limit: 1).value!.data.page
    second_page = query.call(
      change_set_id:,
      after_global_position: first_page.next_global_position,
      limit: 1
    ).value!.data.page
    expect(first_page).to have_attributes(has_more: true)
    expect(first_page.items.sole.enforcement).to eq("merge_gate")
    expect(second_page).to have_attributes(has_more: false, next_global_position: nil)
    expect(second_page.items.sole.enforcement).to eq("verification_gate")

    target = first.dig(:pair, :target)
    filtered = query.call(
      change_set_id:,
      candidate_id: target.fetch(:candidate_id),
      repository_id: "billing",
      enforcement: "verification_gate"
    ).value!.data.page
    expect(filtered.items.map(&:obligation_id)).to eq([ second_result.obligation_id ])

    no_match = query.call(
      change_set_id:,
      candidate_id: "CAN-not-in-this-change-set"
    ).value!.data.page
    expect(no_match.items).to be_empty

    invalid = query.call({}).value!
    expect(invalid).to have_attributes(status: "invalid")
    expect(invalid.data).to have_attributes(code: "invalid_input")
  end

  it "serves a stale unclaimed view, then derives active and expired claim state at query time" do
    created = CandidateObligationScenario.create_obligation(prefix: "obligation-query-claim")
    obligation_id = created.fetch(:result).obligation_id
    projector.call(created.fetch(:event))
    claim_event = Timecop.freeze(Time.utc(2026, 8, 24, 7, 0, 0)) do
      Coordinator::Write::Operations::ExecuteClaimVerificationObligation.new(event_store:).call(
        command_id: "cmd-query-claim",
        actor: { kind: "agent", id: "agent-blue" },
        obligation_id:,
        claim_duration_seconds: 300
      ).value!
      claim_events(obligation_id).sole
    end

    lagging = Timecop.freeze(Time.utc(2026, 8, 24, 7, 1, 0)) do
      query.call(obligation_id:, claim_state: "unclaimed").value!.data.page
    end
    expect(lagging).to have_attributes(
      observed_at: "2026-08-24T07:01:00.000000Z",
      has_more: false
    )
    expect(lagging.items.sole).to have_attributes(status: "open", claim_state: "unclaimed", claim: nil)

    projector.call(claim_event)
    active = Timecop.freeze(Time.utc(2026, 8, 24, 7, 4, 59, 999_999)) do
      query.call(
        obligation_id:,
        claimant_id: "agent-blue",
        claim_state: "active"
      ).value!.data.page
    end
    expect(active.observed_at).to eq("2026-08-24T07:04:59.999999Z")
    expect(active.items.sole).to have_attributes(status: "open", claim_state: "active")
    expect(active.items.sole.claim).to have_attributes(
      claim_id: claim_event.data.fetch("claim_id"),
      claimant_id: "agent-blue",
      fencing_token: 1
    )

    expired = Timecop.freeze(Time.utc(2026, 8, 24, 7, 5, 0)) do
      query.call(obligation_id:, claim_state: "expired").value!.data.page
    end
    active_at_expiry = Timecop.freeze(Time.utc(2026, 8, 24, 7, 5, 0)) do
      query.call(obligation_id:, claim_state: "active").value!.data.page
    end
    expect(expired.items.sole).to have_attributes(status: "open", claim_state: "expired")
    expect(active_at_expiry.items).to be_empty
  end

  it "serves an available open view during terminal lag and converges under an explicit status filter" do
    created = CandidateObligationScenario.create_obligation(
      prefix: "obligation-query-convergence",
      required_evidence: [ "combined_tests" ]
    )
    obligation_id = created.fetch(:result).obligation_id
    projector.call(created.fetch(:event))
    claim = CandidateObligationScenario.claim_obligation(
      created:,
      prefix: "obligation-query-convergence"
    )
    claim_event = verification_history(obligation_id).find do |event|
      event.type == "VerificationObligationClaimed"
    end
    projector.call(claim_event)
    receipt = CandidateObligationScenario.submit_compatibility_assessment(
      created:,
      claim:,
      command_id: "cmd-query-converged-tests"
    )

    lagging_open = query.call(obligation_id:).value!.data.page
    lagging_terminal = query.call(obligation_id:, status: "satisfied").value!.data.page
    expect(lagging_open.items.sole).to have_attributes(status: "open", outcome: nil)
    expect(lagging_open.items.sole.progress).to have_attributes(
      evidence_count: 0,
      passed_evidence_kinds: [],
      missing_evidence_kinds: [ "combined_tests" ]
    )
    expect(lagging_terminal.items).to be_empty

    verification_history(obligation_id)
      .select { _1.type.in?(%w[VerificationEvidenceSubmitted VerificationObligationSatisfied]) }
      .each { projector.call(_1) }

    converged_open = query.call(obligation_id:).value!.data.page
    converged = query.call(obligation_id:, status: "satisfied").value!.data.page
    expect(converged_open.items).to be_empty
    expect(converged.items.sole).to have_attributes(
      status: "satisfied",
      outcome: have_attributes(satisfied_at: receipt.submitted_at)
    )
    expect(converged.items.sole.progress).to have_attributes(
      evidence_count: 1,
      passed_evidence_kinds: [ "combined_tests" ],
      missing_evidence_kinds: []
    )
    expect(converged.items.sole.evidence.global_position).to eq(created.fetch(:event).global_position)
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


  def verification_history(obligation_id)
    CandidateObligationScenario.verification_history(obligation_id)
  end
end
