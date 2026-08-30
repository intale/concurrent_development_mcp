# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::UserUtterancesV1, :read_model do
  subject(:projector) { described_class.new }

  let(:repository_id) { "018f0f4d-4e45-7abc-8def-000000000001" }

  it "stores one concrete attributed utterance and ignores duplicate delivery" do
    payload = Coordinator::Write::Events::UserUtteranceRecordedV1.new(
      message_id: "M-project",
      conversation_id: "C-project",
      text: "Keep raw evidence separate from policy.",
      source: "mcp_client",
      anchors: Coordinator::Write::GuidanceAnchorsV1.new(
        repository_ids: [ repository_id ],
        change_set_id: "CS-1",
        work_item_id: nil,
        attempt_id: nil
      ),
      recorded_at: "2026-08-30T12:00:00.000000Z"
    )
    event = ProjectionEventFactory.build(
      payload:,
      stream: Coordinator::Write::StreamFactory.new.conversation("C-project"),
      stream_revision: 0,
      global_position: 100,
      policy_version: "human-guidance/v1",
      actor_id: "host-1"
    )

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
      repository_ids: [ repository_id ],
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
end
