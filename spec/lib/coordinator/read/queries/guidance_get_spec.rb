# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::GuidanceGet, :event_store, :read_model do
  subject(:query) { described_class.new }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }

  it "serves only the available projection and honestly reports pre-projection absence" do
    Coordinator::Write::Operations::ExecuteRecordGuidance.new(event_store:).call(
      command_id: "cmd-guidance-query",
      actor: { kind: "agent", id: "host-1" },
      message_id: "M-query",
      conversation_id: "C-query",
      source: "agent_forwarded",
      text: "This was forwarded without authenticated provenance.",
      anchors: {
        repository_ids: [],
        change_set_id: nil,
        work_item_id: nil,
        attempt_id: nil
      }
    ).value!

    absent = query.call(message_id: "M-query").value!
    expect(absent.status).to eq("not_found")
    expect(absent.data.code).to eq("guidance_not_observed")

    Coordinator::Read::Projectors::UserUtterancesV1.new.call(guidance_event)
    observed = query.call(message_id: "M-query").value!

    expect(observed.status).to eq("ok")
    expect(observed.data.guidance.to_h).to include(
      message_id: "M-query",
      source: "agent_forwarded",
      policy_status: "evidence_only"
    )
    expect(observed.to_h.keys & %i[active fresh pending projection_status]).to be_empty
  end

  it "returns typed invalid input without consulting an event stream" do
    result = query.call(message_id: "bad id").value!

    expect(result.status).to eq("invalid")
    expect(result.data.code).to eq("invalid_input")
  end

  def guidance_event
    event_store.read(
      streams.conversation("C-query"),
      Coordinator::Write::EventReadCriteria.new(
        event_types: Coordinator::Write::EventQueries::GUIDANCE_MESSAGE_EVENT_TYPES,
        maximum_count: 1,
        direction: :asc
      )
    ).sole
  end
end
