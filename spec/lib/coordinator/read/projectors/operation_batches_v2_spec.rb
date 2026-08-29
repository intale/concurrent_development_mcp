# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::OperationBatchesV2, :event_store, :read_model do
  subject(:projector) { described_class.new }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:repository) { Coordinator::Read::Repositories::OperationBatches.new }
  let(:executor) { Coordinator::Write::Operations::ExecuteOperationBatchCommand.new(event_store:) }

  it "converges under reversed delivery and serves the complete immutable manifest in bounded pages" do
    command = prepared_batch
    expect(executor.call_command(command)).to be_success
    created = history(command.batch_id).sole
    Coordinator::Processes::ProcessManagers::OperationBatchRunner.new(event_store:).call(created)
    events = history(command.batch_id)

    events.reverse_each { projector.call(_1) }
    events.each { projector.call(_1) }

    first = fetch(command.batch_id, limit: 1)
    expect(first).to have_attributes(
      status: "completed_with_errors",
      total: 2,
      succeeded: 1,
      rejected: 1,
      pending: 0,
      not_run: 0,
      has_more: true,
      next_after_index: 0
    )
    expect(first.items.sole).to have_attributes(
      index: 0,
      command_id: "item-1",
      status: "succeeded"
    )
    expect(first.items.sole.arguments).to include(
      command_id: "item-1",
      actor: { kind: "agent", id: "agent-1" },
      name: "review",
      scope: "project:alpha"
    )

    second = fetch(command.batch_id, after_index: first.next_after_index, limit: 1)
    expect(second).to have_attributes(has_more: false, next_after_index: nil)
    expect(second.items.sole).to have_attributes(index: 1, command_id: "item-2", status: "rejected")
    expect(first.created.correlation_id).to eq(created.correlation_id)
    expect(first.terminal.event.type).to eq("OperationBatchCompleted")
    expect(Coordinator::Read::OperationBatch.count).to eq(1)
    expect(Coordinator::Read::OperationBatchItem.count).to eq(2)
    expect(Coordinator::Read::OperationBatchOutcome.count).to eq(2)
    expect(processed_events.count).to eq(events.length)
  end

  it "exposes accepted cancellation before terminal completion and classifies only terminal remainder as not run" do
    command = prepared_batch
    expect(executor.call_command(command)).to be_success
    cancel = Coordinator::Write::Commands::CancelOperationBatch.new(
      command_id: "cancel-command",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "agent-1"),
      batch_id: command.batch_id
    )
    expect(executor.call_command(cancel)).to be_success
    history(command.batch_id).each { projector.call(_1) }

    cancelling = fetch(command.batch_id, limit: 100)
    expect(cancelling).to have_attributes(status: "cancelling", pending: 2, not_run: 0)
    expect(cancelling.items.map(&:status)).to eq(%w[pending pending])
    expect(cancelling.cancellation.event.type).to eq("OperationBatchCancellationRequested")
    expect(cancelling.terminal).to be_nil

    created = history(command.batch_id).find { _1.type == "OperationBatchCreated" }
    Coordinator::Processes::ProcessManagers::OperationBatchRunner.new(event_store:).call(created)
    history(command.batch_id).each { projector.call(_1) }

    cancelled = fetch(command.batch_id, limit: 100)
    expect(cancelled).to have_attributes(status: "cancelled", pending: 0, not_run: 2)
    expect(cancelled.items.map(&:status)).to eq(%w[not_run not_run])
    expect(cancelled.terminal.event.type).to eq("OperationBatchCancelled")
  end

  it "acknowledges pre-semantic creation facts without restoring their removed command schemas" do
    creation = pre_semantic_creation_event
    outcome = pre_semantic_outcome_event(creation)

    projector.call(creation)
    projector.call(outcome)
    projector.call(creation)

    expect(repository.fetch(
      Coordinator::Read::OperationBatchGetQueryV1.new(
        batch_id: creation.stream.stream_id,
        after_index: nil,
        limit: 100
      )
    )).to be_nil
    expect(Coordinator::Read::OperationBatch.sole).to have_attributes(
      batch_id: creation.stream.stream_id,
      manifest_generation: "pre_semantic"
    )
    expect(processed_events.count).to eq(2)
  end

  def prepared_batch
    Coordinator::Write::Operations::PrepareCreateSkillPublishBatch.new.call(input).value!
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

  def fetch(batch_id, after_index: nil, limit:)
    repository.fetch(
      Coordinator::Read::OperationBatchGetQueryV1.new(batch_id:, after_index:, limit:)
    )
  end

  def processed_events
    Coordinator::Read::ProcessedProjectionEvent.where(
      projection_name: "operation_batches",
      projection_version: 2
    )
  end

  def pre_semantic_creation_event
    batch_id = SecureRandom.uuid_v7
    PgEventstore::Event.new(
      id: SecureRandom.uuid_v7,
      type: "OperationBatchCreated",
      stream: PgEventstore::Stream.new(
        context: "DevelopmentCoordination",
        stream_name: "OperationBatch",
        stream_id: batch_id
      ),
      stream_revision: 0,
      global_position: 1,
      data: {
        "batch_id" => batch_id,
        "items" => [
          {
            "command_input" => {
              "schema" => "command-input/v1"
            }
          }
        ]
      },
      metadata: {
        "schema_version" => 1,
        "command_id" => "pre-semantic-batch-command",
        "actor_kind" => "agent",
        "actor_id" => "pre-semantic-importer",
        "recorded_by" => "coordinator",
        "policy_version" => "operation-batch/v1"
      },
      created_at: Time.utc(2026, 8, 25)
    )
  end

  def pre_semantic_outcome_event(creation)
    PgEventstore::Event.new(
      id: SecureRandom.uuid_v7,
      type: "OperationBatchItemSucceeded",
      stream: creation.stream,
      stream_revision: 1,
      global_position: 2,
      data: { "removed_pre_semantic_shape" => true },
      metadata: creation.metadata.merge("command_id" => "pre-semantic-item-command"),
      created_at: Time.utc(2026, 8, 25)
    )
  end
end
