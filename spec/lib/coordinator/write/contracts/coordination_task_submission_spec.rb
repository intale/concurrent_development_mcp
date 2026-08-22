# frozen_string_literal: true

RSpec.describe Coordinator::Write::Contracts::CoordinationTaskSubmission do
  subject(:contract) { described_class.new }

  let(:target_command) do
    Coordinator::Write::Commands::CreateChangeSet.new(
      command_id: "cmd-task-101",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "agent-a"),
      change_set_id: "CS-101",
      goal: "Coordinate billing changes",
      acceptance_criteria: [ "Every target command is durable" ]
    )
  end
  let(:digest) { Coordinator::Write::CommandInputDigest.new }
  let(:event) do
    Coordinator::Write::Events::CoordinationTaskSubmittedV1.new(
      task_id: "01919191-9191-7191-8191-919191919191",
      tool_name: "change_set_create",
      command_id: target_command.command_id,
      canonical_input_digest: digest.call(target_command),
      command_input: digest.document(target_command),
      submitted_at: "2026-08-22T06:30:00.000000Z",
      ttl_ms: nil,
      poll_interval_ms: 500
    )
  end

  it "accepts matching tool, command, and canonical input identities" do
    expect(contract.call(event:)).to be_success
  end

  it "rejects a digest that does not describe the nested command document" do
    changed = described_event(canonical_input_digest: "sha256:#{'0' * 64}")

    expect(contract.call(event: changed).errors.to_h).to include(:event)
  end

  it "is applied when a persisted event payload is reconstructed" do
    payload = event.to_h.merge(tool_name: "work_item_create")

    expect do
      Coordinator::Write::EventSchemaRegistry.new.load(
        type: "CoordinationTaskSubmitted",
        schema_version: 1,
        data: payload
      )
    end.to raise_error(Coordinator::Write::InvalidCoordinationTaskSubmission)
  end

  def described_event(overrides)
    Coordinator::Write::Events::CoordinationTaskSubmittedV1.new(event.to_h.merge(overrides))
  end
end
