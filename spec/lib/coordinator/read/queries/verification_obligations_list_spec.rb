# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::VerificationObligationsList,
               :event_store,
               :read_model do
  subject(:query) { described_class.new }

  let(:projector) { Coordinator::Read::Projectors::VerificationObligationsV1.new }

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
end
