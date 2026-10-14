# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::UserUtterancesV1, :read_model do
  subject(:projector) { described_class.new }
  let(:repository_id) { "018f0f4d-4e45-7abc-8def-000000000001" }
  let(:utterances) { Coordinator::Read::Repositories::UserUtterances.new }

  it "inserts one attributed message, folds its anchors and converges on whole-batch redelivery" do
    recorded = event(Coordinator::Write::Events::UserUtteranceRecordedV2.new(
      message_id: "M-project", conversation_id: "C-project", text: "Keep raw evidence separate from policy.", source: "user"), revision: 0)
    batch = [ recorded, anchor("repository", repository_id, revision: 1), anchor("change_set", "CS-1", revision: 2) ]

    2.times { projector.call(batch) }

    projected = utterances.fetch("M-project")
    expect(projected.to_h).to include(message_id: "M-project", conversation_id: "C-project",
      text: "Keep raw evidence separate from policy.", source: "mcp_client", policy_status: "evidence_only",
      actor: { kind: "agent", id: "host-1", authenticated: false })
    expect(projected.anchors.to_h).to eq(repository_ids: [ repository_id ], change_set_id: "CS-1", work_item_id: nil, attempt_id: nil)
    expect(projected.event.to_h).to include(event_id: recorded.id, type: "UserUtteranceRecorded", stream_id: "C-project", stream_revision: 0)
    expect(Coordinator::Read::UserUtterance.count).to eq(1)
  end

  it "patches only anchor columns in a later batch, preserving message content and source" do
    row = create(:coordinator_read_user_utterance, message_id: "M-project", conversation_id: "C-project",
      anchors: { repository_ids: [], change_set_id: "CS-keep", work_item_id: "W-keep", attempt_id: nil })
    original = row.attributes.except("anchors", "updated_at")
    batch = [ anchor("repository", repository_id, revision: 5), anchor("attempt", "A-new", revision: 6) ]

    2.times { projector.call(batch) }

    expect(row.reload.attributes.except("anchors", "updated_at")).to eq(original)
    expect(row.anchors).to eq("repository_ids" => [ repository_id ], "change_set_id" => "CS-keep",
      "work_item_id" => "W-keep", "attempt_id" => "A-new")
  end

  it "does not reset previously projected anchors on immutable message replay" do
    row = create(:coordinator_read_user_utterance, message_id: "M-project", conversation_id: "C-project",
      anchors: { repository_ids: [ repository_id ], change_set_id: "CS-keep", work_item_id: nil, attempt_id: nil })
    recorded = event(Coordinator::Write::Events::UserUtteranceRecordedV2.new(
      message_id: "M-project", conversation_id: "C-project", text: row.text, source: "user"), revision: 0)

    projector.call([ recorded ])

    expect(row.reload.anchors).to include("repository_ids" => [ repository_id ], "change_set_id" => "CS-keep")
  end

  it "reduces a thousand anchors to one stable membership and one update" do
    row = create(:coordinator_read_user_utterance, message_id: "M-project", conversation_id: "C-project",
      anchors: { repository_ids: [], change_set_id: nil, work_item_id: nil, attempt_id: nil })
    batch = Array.new(1000, anchor("repository", repository_id, revision: 1))
    sql = []
    capture = ->(_name, _start, _finish, _id, payload) { sql << payload.fetch(:sql) }

    ActiveSupport::Notifications.subscribed(capture, "sql.active_record") { projector.call(batch) }

    expect(sql.grep(/\AUPDATE\b/i).length).to eq(1)
    expect(row.reload.anchors.fetch("repository_ids")).to eq([ repository_id ])
  end

  def anchor(kind, id, revision:)
    event(Coordinator::Write::Events::GuidanceMessageAnchoredV1.new(
      message_id: "M-project", conversation_id: "C-project", anchor_kind: kind, anchor_id: id), revision:)
  end

  def event(payload, revision:)
    ProjectionEventFactory.build(payload:, stream: Coordinator::Write::StreamFactory.new.conversation("C-project"),
      stream_revision: revision, global_position: 100 + revision, policy_version: "human-guidance/v1",
      actor_id: "host-1", created_at: Time.utc(2026, 10, 14, 12) + revision)
  end
end
