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
  let(:input_builder) { Coordinator::Write::CommandInputDigest.new }
  let(:event) do
    Coordinator::Write::Events::CoordinationTaskSubmittedV2.new(
      task_id: "01919191-9191-7191-8191-919191919191",
      tool_name: "change_set_create",
      command_id: target_command.command_id,
      command_input: input_builder.document(target_command),
      submitted_at: "2026-08-22T06:30:00.000000Z",
      ttl_ms: nil,
      poll_interval_ms: 500
    )
  end

  it "accepts matching tool, command, and canonical input identities" do
    expect(contract.call(event:)).to be_success
  end

  it "does not persist a digest derivable from the nested command document" do
    expect(event.to_h).not_to have_key(:canonical_input_digest)
  end

  it "rejects a public identity that disagrees with the nested command document" do
    changed = described_event(command_id: "cmd-task-other")

    expect(contract.call(event: changed).errors.to_h).to include(:event)
  end

  it "is applied when a persisted event payload is reconstructed" do
    payload = event.to_h.merge(tool_name: "work_item_create")

    expect do
      Coordinator::Write::EventSchemaRegistry.new.load(
        type: "CoordinationTaskSubmitted",
        schema_version: 2,
        data: payload
      )
    end.to raise_error(Coordinator::Write::InvalidCoordinationTaskSubmission)
  end

  it "continues validating the canonical digest of historical submissions" do
    historical = Coordinator::Write::Events::CoordinationTaskSubmittedV1.new(
      event.to_h.merge(
        canonical_input_digest: "sha256:#{'0' * 64}"
      )
    )

    expect(contract.call(event: historical).errors.to_h).to include(:event)
  end

  def described_event(overrides)
    Coordinator::Write::Events::CoordinationTaskSubmittedV2.new(event.to_h.merge(overrides))
  end
end
