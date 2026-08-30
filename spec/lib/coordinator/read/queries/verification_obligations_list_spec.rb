# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::VerificationObligationsList, :read_model do
  subject(:query) { described_class.new }

  it "serves empty pages and cursor-pages obligations through ANDed filters" do
    change_set_id = "CS-obligation-query"
    first = create(
      :coordinator_read_verification_obligation,
      obligation_id: "OBL-query-1",
      change_set_id:,
      enforcement: "merge_gate",
      event_global_position: 1_200
    )
    second = create(
      :coordinator_read_verification_obligation,
      obligation_id: "OBL-query-2",
      change_set_id:,
      enforcement: "verification_gate",
      event_global_position: 1_201
    )

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

    filtered = query.call(
      change_set_id:,
      candidate_id: second.target_candidate_id,
      repository_id: second.target_repository_id,
      enforcement: "verification_gate"
    ).value!.data.page
    expect(filtered.items.map(&:obligation_id)).to eq([ second.obligation_id ])

    expect(query.call(change_set_id: "CS-absent").value!.data.page.items).to be_empty
    invalid = query.call({}).value!
    expect(invalid).to have_attributes(status: "invalid")
    expect(invalid.data).to have_attributes(code: "invalid_input")
    expect(first.obligation_id).to eq("OBL-query-1")
  end

  it "derives unclaimed, active, and expired claim state at query time" do
    unclaimed = create(
      :coordinator_read_verification_obligation,
      obligation_id: "OBL-query-unclaimed"
    )
    claimed = create(
      :coordinator_read_verification_obligation,
      :claimed,
      obligation_id: "OBL-query-claimed",
      claimant_id: "agent-blue",
      claim_claimed_at_domain: Time.utc(2026, 8, 24, 7),
      claim_expires_at_domain: Time.utc(2026, 8, 24, 7, 5)
    )

    at_four_fifty_nine = Timecop.freeze(Time.utc(2026, 8, 24, 7, 4, 59, 999_999)) do
      query.call(obligation_id: claimed.obligation_id, claim_state: "active").value!.data.page
    end
    expect(at_four_fifty_nine.observed_at).to eq("2026-08-24T07:04:59.999999Z")
    expect(at_four_fifty_nine.items.sole).to have_attributes(status: "open", claim_state: "active")
    expect(at_four_fifty_nine.items.sole.claim).to have_attributes(
      claim_id: claimed.claim_id,
      claimant_id: "agent-blue",
      fencing_token: 1
    )

    at_expiry = Timecop.freeze(Time.utc(2026, 8, 24, 7, 5)) do
      query.call(obligation_id: claimed.obligation_id, claim_state: "expired").value!.data.page
    end
    active_at_expiry = Timecop.freeze(Time.utc(2026, 8, 24, 7, 5)) do
      query.call(obligation_id: claimed.obligation_id, claim_state: "active").value!.data.page
    end
    available_unclaimed = query.call(
      obligation_id: unclaimed.obligation_id,
      claim_state: "unclaimed"
    ).value!.data.page

    expect(at_expiry.items.sole).to have_attributes(status: "open", claim_state: "expired")
    expect(active_at_expiry.items).to be_empty
    expect(available_unclaimed.items.sole).to have_attributes(claim_state: "unclaimed", claim: nil)
  end

  it "serves a complete available terminal view and projected evidence" do
    obligation = create(
      :coordinator_read_verification_obligation,
      :claimed,
      :satisfied,
      obligation_id: "OBL-query-satisfied",
      required_evidence: [ "combined_tests" ]
    )
    evidence_id = SecureRandom.uuid_v7
    create(
      :coordinator_read_verification_obligation_evidence_item,
      evidence_id:,
      obligation_id: obligation.obligation_id,
      obligation_event: obligation.event,
      submission: evidence_submission(obligation, evidence_id:)
    )

    open_page = query.call(obligation_id: obligation.obligation_id).value!.data.page
    satisfied = query.call(
      obligation_id: obligation.obligation_id,
      status: "satisfied"
    ).value!.data.page

    expect(open_page.items).to be_empty
    expect(satisfied.items.sole).to have_attributes(
      status: "satisfied",
      outcome: have_attributes(satisfied_at: "2026-08-30T12:03:00.000000Z")
    )
    expect(satisfied.items.sole.progress).to have_attributes(
      evidence_count: 1,
      passed_evidence_kinds: [ "combined_tests" ],
      missing_evidence_kinds: []
    )
    expect(satisfied.items.sole.submitted_evidence.sole).to have_attributes(
      evidence_kind: "combined_tests",
      assessment: have_attributes(conclusion: "passed")
    )
  end

  def evidence_submission(obligation, evidence_id:)
    {
      "obligation_id" => obligation.obligation_id,
      "obligation_event" => obligation.event,
      "evidence_id" => evidence_id,
      "evidence_kind" => "combined_tests",
      "claim" => {
        "claim_id" => obligation.claim_id,
        "claimant_id" => obligation.claimant_id,
        "fencing_token" => obligation.claim_fencing_token,
        "claim_event" => obligation.claim_event
      },
      "source_candidate" => obligation.obligation.fetch("source_candidate"),
      "target_candidate" => obligation.obligation.fetch("target_candidate"),
      "policy" => obligation.obligation.fetch("policy"),
      "obligation_validity_input_digest" => obligation.obligation.fetch("validity_input_digest"),
      "assessment" => {
        "evidence_kind" => "combined_tests",
        "producer" => { "name" => "factory-suite", "version" => "1.0" },
        "run_id" => "run-factory",
        "test_suite_digest" => "sha256:#{'7' * 64}",
        "environment_digest" => "sha256:#{'8' * 64}",
        "dependency_graph_digest" => "sha256:#{'9' * 64}",
        "result_digest" => "sha256:#{'4' * 64}",
        "conclusion" => "passed",
        "findings" => [],
        "produced_at" => "2026-08-30T12:02:00.000000Z"
      },
      "assessment_input_digest" => "sha256:#{'5' * 64}",
      "submitted_at" => "2026-08-30T12:02:00.000000Z"
    }
  end
end
