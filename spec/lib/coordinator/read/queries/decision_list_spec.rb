# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::DecisionList, :read_model do
  subject(:query) { described_class.new }

  DECISION_LIST_REPOSITORY_ID = "018f0f4d-4e45-7abc-8def-000000000021"
  DECISION_LIST_OTHER_REPOSITORY_ID = "018f0f4d-4e45-7abc-8def-000000000022"

  it "discovers active Decision topics associated directly and through projected coordination" do
    change_set_id = "CS-decision-discovery"
    create(
      :coordinator_read_coord_context,
      change_set_id:,
      work_item_id: "W-decision-discovery",
      attempt_id: "A-decision-discovery",
      repository_id: DECISION_LIST_REPOSITORY_ID
    )
    create(
      :coordinator_read_decision_definition,
      :active,
      decision_id: "D-impact",
      topic_id: "candidate.impact_policy",
      change_set_id:,
      enforcement_level: "advisory"
    )
    create(
      :coordinator_read_decision_definition,
      :active,
      decision_id: "D-testing",
      repository_id: DECISION_LIST_REPOSITORY_ID
    )

    impact = query.call(
      repository_id: DECISION_LIST_REPOSITORY_ID,
      topic_id: "candidate.impact_policy",
      policy_status: "active"
    ).value!
    expect(impact).to have_attributes(status: "ok")
    expect(impact.warnings).to contain_exactly(match(/projection-derived/))
    expect(impact.data.page.items.map(&:decision_id)).to eq([ "D-impact" ])
    expect(impact.next_actions.sole).to have_attributes(
      tool: "decision_get",
      arguments: have_attributes(decision_id: "D-impact")
    )

    first = query.call(repository_id: DECISION_LIST_REPOSITORY_ID, limit: 1).value!
    expect(first.data.page).to have_attributes(has_more: true, next_decision_id: "D-impact")
    second = query.call(
      repository_id: DECISION_LIST_REPOSITORY_ID,
      after_decision_id: first.data.page.next_decision_id,
      limit: 1
    ).value!
    expect([ *first.data.page.items, *second.data.page.items ].map(&:decision_id)).to eq(
      %w[D-impact D-testing]
    )

    unrelated = query.call(repository_id: DECISION_LIST_OTHER_REPOSITORY_ID).value!
    expect(unrelated.data.page.items).to be_empty
  end

  it "serves only the currently available Decision rows" do
    create(
      :coordinator_read_decision_definition,
      :active,
      decision_id: "D-available",
      repository_id: DECISION_LIST_REPOSITORY_ID
    )

    result = query.call(repository_id: DECISION_LIST_REPOSITORY_ID).value!

    expect(result.data.page.items.map(&:decision_id)).to eq([ "D-available" ])
    expect(result.to_h.keys & %i[fresh pending projection_status stream_revision]).to be_empty
  end

  it "resolves attempt-scoped Decisions through unbounded Attempt history" do
    change_set_id = "CS-decision-history"
    work_item_id = "W-decision-history"
    attempt_id = "A-decision-history"
    context = create(
      :coordinator_read_coord_context,
      change_set_id:,
      work_item_id:,
      repository_id: DECISION_LIST_REPOSITORY_ID
    )
    context.update!(document: context.document.merge("attempts" => []))
    create(:coordinator_read_attempt_history, attempt_id:, change_set_id:, work_item_id:)
    create(
      :coordinator_read_decision_definition,
      decision_id: "D-attempt-history",
      repository_id: nil,
      attempt_id:
    )

    result = query.call(repository_id: DECISION_LIST_REPOSITORY_ID).value!

    expect(result.data.page.items.map(&:decision_id)).to eq([ "D-attempt-history" ])
  end

  it "returns typed invalid filters and an empty available page" do
    invalid = query.call(
      repository_id: "0198f5b8-57ab-7def-8abc-1234567890ab",
      topic_id: "bad topic",
      policy_status: "retired",
      limit: 51
    ).value!
    empty = query.call(repository_id: DECISION_LIST_REPOSITORY_ID).value!

    expect(invalid).to have_attributes(status: "invalid")
    expect(invalid.data).to have_attributes(code: "invalid_input")
    expect(empty.data.page).to have_attributes(items: [], has_more: false)
  end
end
