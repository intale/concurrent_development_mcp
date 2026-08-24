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
end
