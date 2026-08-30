# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::CommandReceiptsV1, :read_model do
  subject(:projector) { described_class.new }

  it "stores a concrete validated completion once and exposes the typed receipt" do
    completion = Coordinator::Write::Events::CommandCompletedV1.new(
      command_id: "cmd-100",
      tool_name: "change_set_create",
      canonical_input_digest: "sha256:#{'a' * 64}",
      status: "ok",
      summary: "Change Set created.",
      receipt: "command:cmd-100",
      data: Coordinator::Write::CommandReceiptData::ChangeSet.new(change_set_id: "CS-100"),
      warnings: [],
      next_actions: [],
      emitted_events: [],
      completed_at: "2026-08-30T12:00:00.000000Z"
    )
    event = ProjectionEventFactory.build(
      payload: completion,
      stream: Coordinator::Write::StreamFactory.new.command("cmd-100"),
      stream_revision: 0,
      global_position: 100,
      policy_version: "command-completion/v1"
    )

    projector.call(event)
    projector.call(event)

    projected = Coordinator::Read::Repositories::CommandReceipts.new.fetch("cmd-100")
    expect(projected).to eq(completion)
    expect(Coordinator::Read::CommandReceipt.count).to eq(1)
    expect(
      Coordinator::Read::ProcessedProjectionEvent.where(projection_name: "command_receipts").count
    ).to eq(1)
  end
end
