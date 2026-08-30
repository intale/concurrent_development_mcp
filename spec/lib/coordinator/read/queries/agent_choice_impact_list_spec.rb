# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::AgentChoiceImpactList, :read_model do
  subject(:query) { described_class.new }

  it "serves the latest available assessment rows independently from AgentChoice lifecycle rows" do
    attempt_id = "A-impact-query-lag"
    choice_id = "CHO-impact-query-lag"
    create(:coordinator_read_agent_choice, :accepted, choice_id:)

    empty = query.call(attempt_id:).value!.data.page
    expect(empty).to have_attributes(items: [], next_global_position: nil, has_more: false)

    create(
      :coordinator_read_agent_choice_impact,
      attempt_id:,
      choice_id:,
      event_global_position: 700
    )
    available = query.call(attempt_id:).value!.data.page

    expect(available.items.sole).to have_attributes(choice_id:, outcome: "invalidated")
    choice = Coordinator::Read::Queries::AgentChoiceGet.new.call(choice_id:).value!.data.choice
    expect(choice).to have_attributes(observation_status: "accepted", invalidation: nil)
  end

  it "pages assessments by opaque global-position cursor with strict limits" do
    attempt_id = "A-impact-query-page"
    choice_ids = Array.new(3) { "CHO-impact-query-page-#{_1}" }
    choice_ids.each_with_index do |choice_id, index|
      create(
        :coordinator_read_agent_choice_impact,
        choice_id:,
        attempt_id:,
        event_global_position: 710 + index
      )
    end

    first = query.call(attempt_id:, limit: 2).value!.data.page
    expect(first).to have_attributes(has_more: true)
    expect(first.items.map(&:choice_id)).to eq(choice_ids.first(2))
    expect(first.next_global_position).to eq(first.items.last.assessment_evidence.global_position)

    second = query.call(
      attempt_id:,
      after_global_position: first.next_global_position,
      limit: 2
    ).value!.data.page
    expect(second).to have_attributes(
      items: contain_exactly(have_attributes(choice_id: choice_ids.last)),
      next_global_position: nil,
      has_more: false
    )
    expect(first.items.first.source_actor).to have_attributes(kind: "orchestrator", id: "guidance-host")
  end

  it "returns typed invalid input" do
    result = query.call(attempt_id: "bad id", limit: 101).value!

    expect(result).to have_attributes(status: "invalid")
    expect(result.data).to have_attributes(code: "invalid_input")
  end
end
