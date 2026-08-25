# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteOperationBatchCommand, :event_store do
  subject(:operation) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:preparer) { Coordinator::Write::Operations::PrepareCreateSkillPublishBatch.new }

  it "atomically creates a bounded Batch and its Command completion with exact replay" do
    command = preparer.call(input).value!

    first = operation.call_command(command)
    replay = operation.call_command(command)

    expect(first).to be_success
    expect(replay).to be_success
    expect(replay.value!).to eq(first.value!)
    expect(first.value!.data).to have_attributes(
      batch_id: command.batch_id,
      target_tool: "skill_publish",
      total: 2,
      status: "accepted"
    )
    expect(batch_events(command.batch_id).map(&:type)).to eq([ "OperationBatchCreated" ])
    expect(command_events(command.command_id).map(&:type)).to eq([ "CommandCompleted" ])
  end

  it "rejects command and Batch ID reuse without adding Batch facts" do
    original = preparer.call(input).value!
    changed_command = preparer.call(
      input(items: [ item, item(command_id: "item-2", name: "changed") ])
    ).value!
    conflicting_batch = preparer.call(
      input(command_id: "another-batch-command", items: [ item(command_id: "item-3") ])
    ).value!

    expect(operation.call_command(original)).to be_success
    expect(operation.call_command(changed_command).failure.code).to eq(:command_id_reused)
    expect(operation.call_command(conflicting_batch).failure.code).to eq(:operation_batch_id_conflict)
    expect(batch_events(original.batch_id).length).to eq(1)
  end

  def input(**overrides)
    @batch_id ||= SecureRandom.uuid_v7
    {
      command_id: "batch-command",
      actor: { kind: "agent", id: "agent-1" },
      batch_id: @batch_id,
      items: [ item, item(command_id: "item-2", name: "second") ]
    }.merge(overrides)
  end

  def item(**overrides)
    {
      command_id: "item-1",
      actor: { kind: "agent", id: "agent-1" },
      name: "review",
      scope: "project:alpha",
      expected_revision: 0,
      description: "Review a change",
      instructions: "Inspect the complete diff.",
      assets: []
    }.merge(overrides)
  end

  def batch_events(batch_id)
    event_store.read(streams.operation_batch(batch_id), Coordinator::Write::EventQueries::OPERATION_BATCH_HISTORY)
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_COMPLETION)
  end
end
