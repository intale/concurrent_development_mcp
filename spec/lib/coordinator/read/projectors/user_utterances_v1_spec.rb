# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::UserUtterancesV1, :event_store, :read_model do
  subject(:projector) { described_class.new }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:input) do
    {
      command_id: "cmd-guidance-project",
      actor: { kind: "agent", id: "host-1" },
      message_id: "M-project",
      conversation_id: "C-project",
      source: "mcp_client",
      text: "Keep raw evidence separate from policy.",
      anchors: {
        repository_ids: [ RepositoryScenario::DEFAULT_REPOSITORY_ID ],
        change_set_id: "CS-1",
        work_item_id: nil,
        attempt_id: nil
      }
    }
  end

  it "stores one immutable attributed row and ignores duplicate delivery" do
    Coordinator::Write::Operations::ExecuteRecordGuidance.new(event_store:).call(input).value!
    event = guidance_event

    projector.call(event)
    projector.call(event)

    projected = Coordinator::Read::Repositories::UserUtterances.new.fetch("M-project")
    expect(projected.to_h).to include(
      message_id: "M-project",
      conversation_id: "C-project",
      text: "Keep raw evidence separate from policy.",
      source: "mcp_client",
      policy_status: "evidence_only",
      actor: { kind: "agent", id: "host-1", authenticated: false }
    )
    expect(projected.anchors.to_h).to eq(
      repository_ids: [ RepositoryScenario::DEFAULT_REPOSITORY_ID ],
      change_set_id: "CS-1",
      work_item_id: nil,
      attempt_id: nil
    )
    expect(projected.event.to_h).to include(
      event_id: event.id,
      type: "UserUtteranceRecorded",
      stream_context: "HumanGuidance",
      stream_name: "Conversation",
      stream_id: "C-project",
      stream_revision: 0
    )
    expect(Coordinator::Read::UserUtterance.count).to eq(1)
    expect(
      Coordinator::Read::ProcessedProjectionEvent.where(projection_name: "user_utterances").count
    ).to eq(1)
  end

  def guidance_event
    event_store.read(
      streams.conversation("C-project"),
      Coordinator::Write::EventReadCriteria.new(
        event_types: Coordinator::Write::EventQueries::GUIDANCE_MESSAGE_EVENT_TYPES,
        maximum_count: 1,
        direction: :asc
      )
    ).sole
  end
end
