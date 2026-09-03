# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteOperationBatchCommand, :event_store do
  subject(:operation) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:preparer) { Coordinator::Write::Operations::PrepareCreateSkillPublishBatch.new }

  it "atomically creates a bounded Batch and registers its UUIDv7 item Commands" do
    command = preparer.call(input).value!

    first = operation.call_command(command)

    expect(first).to be_success
    expect(first.value!.emitted_events.map(&:type)).to eq([ "OperationBatchCreated" ])
    expect(first.value!.data).to have_attributes(
      batch_id: command.batch_id,
      target_tool: "skill_publish",
      total: 2,
      status: "accepted"
    )
    created = batch_events(command.batch_id).sole
    expect(created.type).to eq("OperationBatchCreated")
    expect(created.metadata.fetch("schema_version")).to eq(2)
    expect(created.data.keys).to contain_exactly("batch_id", "target_tool", "page_size", "items")
    items = load(created).items
    expect(items.map(&:request_id)).to eq(%w[item-1 item-2])
    expect(items.map(&:command_id)).to all(match(Coordinator::Shared::Types::UUID_V7_PATTERN))
    expect(items.map { command_events(_1.command_id).map(&:type) }).to eq([
      [ "CommandRegistered" ],
      [ "CommandRegistered" ]
    ])
  end

  it "leaves public replay to the Command lifecycle and rejects direct Batch ID reuse" do
    original = preparer.call(input).value!
    changed_command = preparer.call(
      input(items: [ item, item(command_id: "item-2", name: "changed") ])
    ).value!
    conflicting_batch = preparer.call(
      input(command_id: "another-batch-command", items: [ item(command_id: "item-3") ])
    ).value!

    expect(operation.call_command(original)).to be_success
    expect(operation.call_command(original).failure.code).to eq(:operation_batch_id_conflict)
    expect(operation.call_command(changed_command).failure.code).to eq(:operation_batch_id_conflict)
    expect(operation.call_command(conflicting_batch).failure.code).to eq(:operation_batch_id_conflict)
    expect(batch_events(original.batch_id).length).to eq(1)
  end

  it "projects a batch-item result from its persisted Batch instruction without a Task submission" do
    batch_command = preparer.call(input(items: [ item ])).value!
    expect(operation.call_command(batch_command)).to be_success
    created = batch_events(batch_command.batch_id).sole
    batch_item = load(created).items.sole
    target = Coordinator::Write::Tasks::TargetCommandBuilder.new.call(batch_item.command_input)
    execution = Coordinator::Write::Tasks::TargetExecutor.new(event_store:).call(
      target,
      caused_by: created
    ).value!

    source = Coordinator::Read::CommandResults::SourceLoader.new(event_store:).call(
      execution.terminal_event
    )
    result = Coordinator::Read::CommandResults::Assembler.new(event_store:).call(source)

    expect(source.command).to eq(target)
    expect(result).to have_attributes(
      command_id: "item-1",
      tool_name: "skill_publish",
      status: "ok"
    )
    expect(result.data).to have_attributes(name: "review", scope: "project:alpha")
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
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_HISTORY)
  end

  def load(event)
    Coordinator::Write::EventSchemaRegistry.new.load(
      type: event.type,
      schema_version: event.metadata.fetch("schema_version"),
      data: event.data
    )
  end
end
