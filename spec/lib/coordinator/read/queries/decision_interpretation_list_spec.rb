# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::DecisionInterpretationList, :read_model do
  subject(:query) { described_class.new }

  it "serves available proposals in revision pages without a freshness gate" do
    message_id = "M-query-interpretation"
    absent = query.call(message_id:).value!
    expect(absent.status).to eq("not_found")
    expect(absent.data.code).to eq("interpretations_not_observed")

    create(
      :coordinator_read_decision_interpretation,
      interpretation_id: "I-query-A",
      message_id:,
      stream_revision: 0
    )
    create(
      :coordinator_read_decision_interpretation,
      interpretation_id: "I-query-B",
      message_id:,
      stream_revision: 1,
      assessment: {
        "status" => "confirmation_required",
        "reasons" => [ "blocking_enforcement_requires_confirmation" ],
        "questions" => []
      },
      proposal_status: "confirmation_required"
    )
    create(
      :coordinator_read_decision_interpretation,
      interpretation_id: "I-query-C",
      message_id:,
      stream_revision: 2
    )

    first = query.call(message_id:, after_revision: -1, limit: 2).value!
    expect(first.status).to eq("ok")
    expect(first.data.page.interpretations.map(&:interpretation_id)).to eq(%w[I-query-A I-query-B])
    expect(first.data.page.interpretations.last.assessment.status).to eq("confirmation_required")
    expect(first.data.page.next_after_revision).to eq(1)

    second = query.call(
      message_id:,
      after_revision: first.data.page.next_after_revision,
      limit: 2
    ).value!
    expect(second.data.page.interpretations.map(&:interpretation_id)).to eq([ "I-query-C" ])
    expect(second.data.page.next_after_revision).to be_nil
    expect(second.to_h.keys & %i[active fresh pending projection_status]).to be_empty

    empty_tail = query.call(message_id:, after_revision: 3, limit: 2).value!
    expect(empty_tail.data.page.interpretations).to be_empty
  end

  it "returns typed invalid input" do
    result = query.call(message_id: "bad id", limit: 101).value!

    expect(result.status).to eq("invalid")
    expect(result.data.code).to eq("invalid_input")
  end
end
