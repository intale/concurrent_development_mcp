# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::DecisionInterpretationList, :event_store, :read_model do
  subject(:query) { described_class.new }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:projector) { Coordinator::Read::Projectors::DecisionInterpretationsV1.new }

  before do
    Coordinator::Write::Operations::ExecuteRecordGuidance.new(event_store:).call(
      command_id: "cmd-guidance-query-interpretation",
      actor: { kind: "user", id: "user-label" },
      message_id: "M-query-interpretation",
      conversation_id: "C-query-interpretation",
      source: "mcp_client",
      text: "Use RSpec.",
      anchors: {
        repository_ids: [ "0198f5b8-57ab-7def-8abc-1234567890ab" ],
        change_set_id: "CS-1",
        work_item_id: nil,
        attempt_id: nil
      }
    ).value!
  end

  it "serves available proposals in revision pages without a freshness gate" do
    absent = query.call(message_id: "M-query-interpretation").value!
    expect(absent.status).to eq("not_found")
    expect(absent.data.code).to eq("interpretations_not_observed")

    propose(command_id: "cmd-proposal-query-a", interpretation_id: "I-query-A")
    propose(
      command_id: "cmd-proposal-query-b",
      interpretation_id: "I-query-B",
      effect: "forbid",
      modality: "must_not",
      enforcement: InterpretationInput.advisory_enforcement.merge(
        level: "merge_gate",
        on_violation: "block"
      )
    )
    propose(command_id: "cmd-proposal-query-c", interpretation_id: "I-query-C")
    interpretation_events.each { projector.call(_1) }

    first = query.call(
      message_id: "M-query-interpretation",
      after_revision: -1,
      limit: 2
    ).value!
    expect(first.status).to eq("ok")
    expect(first.data.page.interpretations.map(&:interpretation_id)).to eq(
      %w[I-query-A I-query-B]
    )
    expect(first.data.page.interpretations.last.assessment.status).to eq(
      "confirmation_required"
    )
    expect(first.data.page.next_after_revision).to eq(1)

    second = query.call(
      message_id: "M-query-interpretation",
      after_revision: first.data.page.next_after_revision,
      limit: 2
    ).value!
    expect(second.status).to eq("ok")
    expect(second.data.page.interpretations.map(&:interpretation_id)).to eq([ "I-query-C" ])
    expect(second.data.page.next_after_revision).to be_nil
    expect(second.to_h.keys & %i[active fresh pending projection_status]).to be_empty

    empty_tail = query.call(
      message_id: "M-query-interpretation",
      after_revision: 3,
      limit: 2
    ).value!
    expect(empty_tail.status).to eq("ok")
    expect(empty_tail.data.page.interpretations).to be_empty
  end

  it "returns typed invalid input without consulting event authority" do
    result = query.call(message_id: "bad id", limit: 101).value!

    expect(result.status).to eq("invalid")
    expect(result.data.code).to eq("invalid_input")
  end

  def propose(**overrides)
    input = InterpretationInput.build(
      source_message_id: "M-query-interpretation",
      source_span: { start_character: 4, end_character: 9, text: "RSpec" },
      **overrides
    )
    Coordinator::Write::Operations::ExecuteProposeDecisionInterpretation.new(event_store:).call(
      input
    ).value!
  end

  def interpretation_events
    event_store.read(
      streams.interpretation("M-query-interpretation"),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[DecisionInterpretationProposed DecisionClarificationRequired],
        maximum_count: 20,
        direction: :asc
      )
    )
  end
end
