# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::DecisionGet, :event_store, :read_model do
  subject(:query) { described_class.new }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:projector) { Coordinator::Read::Projectors::DecisionGovernanceV1.new }

  it "serves each latest available projection stage without consulting write authority" do
    activation = seed_activation
    recorded, activated = decision_events

    absent = query.call(decision_id: "D-query").value!
    expect(absent).to have_attributes(status: "not_found")
    expect(absent.data).to have_attributes(code: "decision_not_observed")

    projector.call(recorded)
    recorded_result = query.call(decision_id: "D-query").value!
    expect(recorded_result).to have_attributes(status: "ok")
    expect(recorded_result.data.decision).to have_attributes(
      policy_status: "recorded",
      activated: nil
    )

    projector.call(activated)
    active_result = query.call(decision_id: "D-query").value!
    expect(active_result.data.decision).to have_attributes(
      policy_status: "active",
      slot: activation.data.slot
    )
    expect(active_result.to_h.keys & %i[active fresh pending projection_status stream_revision]).to be_empty
  end

  it "returns typed invalid input without reading pg_eventstore" do
    result = query.call(decision_id: "bad id").value!

    expect(result).to have_attributes(status: "invalid")
    expect(result.data).to have_attributes(code: "invalid_input")
  end

  def seed_activation
    execute(Coordinator::Write::Operations::ExecuteRecordGuidance, {
      command_id: "cmd-guidance-query-decision",
      actor: { kind: "user", id: "user-label" },
      message_id: "M-query-decision",
      conversation_id: "C-query-decision",
      source: "mcp_client",
      text: "Use RSpec.",
      anchors: {
        repository_ids: [ "billing" ],
        change_set_id: nil,
        work_item_id: nil,
        attempt_id: nil
      }
    })
    execute(Coordinator::Write::Operations::ExecuteProposeDecisionInterpretation, InterpretationInput.build(
      command_id: "cmd-proposal-query-decision",
      interpretation_id: "I-query-decision",
      source_message_id: "M-query-decision"
    ))
    execute(Coordinator::Write::Operations::ExecuteAdjudicateDecisionInterpretation, InterpretationInput.adjudication(
      command_id: "cmd-adjudication-query-decision",
      source_message_id: "M-query-decision",
      interpretation_id: "I-query-decision"
    ))
    execute(Coordinator::Write::Operations::ExecuteActivateDecision, InterpretationInput.activation(
      command_id: "cmd-activation-query-decision",
      decision_id: "D-query",
      interpretation_id: "I-query-decision"
    ))
  end

  def execute(operation_class, input)
    operation_class.new(event_store:).call(input).value!
  end

  def decision_events
    event_store.read(streams.decision("D-query"), Coordinator::Write::EventQueries::DECISION_EXISTENCE)
  end
end
