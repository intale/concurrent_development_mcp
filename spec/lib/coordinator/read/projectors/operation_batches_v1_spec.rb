# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::OperationBatchesV2, :event_store, :read_model do
  subject(:projector) { described_class.new }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:repository) { Coordinator::Read::Repositories::OperationBatches.new }

  it "converges under reversed and duplicate delivery while serving paged available progress" do
    command = Coordinator::Write::Operations::PrepareCreateSkillPublishBatch.new.call(input).value!
    executor = Coordinator::Write::Operations::ExecuteOperationBatchCommand.new(event_store:)
    expect(executor.call_command(command)).to be_success
    created = history(command.batch_id).sole
    Coordinator::Processes::ProcessManagers::OperationBatchRunner.new(event_store:).call(created)
    events = history(command.batch_id)

    events.reverse_each { projector.call(_1) }
    events.each { projector.call(_1) }

    query = Coordinator::Read::OperationBatchGetQueryV1.new(
      batch_id: command.batch_id,
      after_index: nil,
      limit: 1
    )
    batch = repository.fetch(query)
    expect(batch).to have_attributes(
      status: "completed_with_errors",
      total: 2,
      succeeded: 1,
      rejected: 1,
      pending: 0,
      not_run: 0,
      has_more: true,
      next_after_index: 0
    )
    expect(batch.items.sole).to have_attributes(index: 0, status: "succeeded")
    expect(batch.created.correlation_id).to eq(created.correlation_id)
    expect(batch.terminal.event.type).to eq("OperationBatchCompleted")
    expect(Coordinator::Read::OperationBatch.count).to eq(1)
    expect(Coordinator::Read::OperationBatchOutcome.count).to eq(2)
    expect(processed_events.count).to eq(events.length)
  end

  def input
    {
      command_id: "batch-command",
      actor: { kind: "agent", id: "agent-1" },
      batch_id: SecureRandom.uuid_v7,
      items: [
        item(command_id: "item-1", expected_revision: 0),
        item(command_id: "item-2", expected_revision: 0)
      ]
    }
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

  def history(batch_id)
    event_store.read(streams.operation_batch(batch_id), Coordinator::Write::EventQueries::OPERATION_BATCH_HISTORY)
  end

  def processed_events
    Coordinator::Read::ProcessedProjectionEvent.where(
      projection_name: "operation_batches",
      projection_version: 2
    )
  end
end
