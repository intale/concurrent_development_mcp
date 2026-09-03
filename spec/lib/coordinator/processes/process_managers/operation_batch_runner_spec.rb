# frozen_string_literal: true

RSpec.describe Coordinator::Processes::ProcessManagers::OperationBatchRunner, :event_store do
  subject(:runner) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:preparer) { Coordinator::Write::Operations::PrepareCreateSkillPublishBatch.new }
  let(:batch_executor) { Coordinator::Write::Operations::ExecuteOperationBatchCommand.new(event_store:) }

  it "executes items sequentially, records a public denial, and converges on redelivery" do
    command = preparer.call(
      input(
        items: [
          item(command_id: "item-1", expected_revision: 0),
          item(command_id: "item-2", expected_revision: 0)
        ]
      )
    ).value!
    expect(batch_executor.call_command(command)).to be_success
    created = batch_events(command.batch_id).sole

    runner.call(created)
    first_history = batch_events(command.batch_id)
    runner.call(created)

    expect(first_history.map(&:type)).to eq([
      "OperationBatchCreated",
      "OperationBatchItemSucceeded",
      "OperationBatchItemRejected",
      "OperationBatchCompleted"
    ])
    expect(batch_events(command.batch_id).map(&:id)).to eq(first_history.map(&:id))
    completed = load(first_history.last)
    expect(completed.to_h).to eq(batch_id: command.batch_id)
    first_history.select { %w[OperationBatchItemSucceeded OperationBatchItemRejected].include?(_1.type) }
      .each do |event|
        expect(event.markers).to include("batch-item:#{command.batch_id}:#{event.data.fetch("index")}")
      end
    expect(skill_events.length).to eq(1)
  end

  it "observes a cancellation from the authoritative Batch stream before starting an item" do
    command = preparer.call(input(items: [ item ])).value!
    expect(batch_executor.call_command(command)).to be_success
    created = batch_events(command.batch_id).sole
    cancellation = Coordinator::Write::Commands::CancelOperationBatch.new(
      command_id: "cancel-command",
      actor: Coordinator::Write::Commands::Actor.new(kind: "user", id: "user-1"),
      batch_id: command.batch_id
    )
    expect(batch_executor.call_command(cancellation)).to be_success

    runner.call(created)

    expect(batch_events(command.batch_id).map(&:type)).to eq([
      "OperationBatchCreated",
      "OperationBatchCancellationRequested",
      "OperationBatchCancelled"
    ])
    expect(skill_events).to be_empty
  end

  it "replays a target that committed before its Batch outcome and converges once" do
    command = preparer.call(input(items: [ item ])).value!
    expect(batch_executor.call_command(command)).to be_success
    created = batch_events(command.batch_id).sole
    unrelated_command = preparer.call(
      input(
        command_id: "unrelated-batch-command",
        batch_id: SecureRandom.uuid_v7,
        items: [ item(command_id: "unrelated-item", name: "unrelated") ]
      )
    ).value!
    expect(batch_executor.call_command(unrelated_command)).to be_success
    unrelated_created = batch_events(unrelated_command.batch_id).sole
    target = Coordinator::Write::Tasks::TargetCommandBuilder.new.call(load(created).items.sole.command_input)
    target_executor = Coordinator::Write::Tasks::TargetExecutor.new(event_store:)

    expect(target_executor.call(target, caused_by: unrelated_created)).to be_success
    target_terminal = command_events(target.command_id).last
    expect(target_terminal.type).to eq("CommandSucceeded")
    expect(target_terminal.correlation_id).to eq(unrelated_created.correlation_id)

    runner.call(created)
    runner.call(created)

    history = batch_events(command.batch_id)
    expect(history.map(&:type)).to eq([
      "OperationBatchCreated",
      "OperationBatchItemSucceeded",
      "OperationBatchCompleted"
    ])
    outcome = history.fetch(1)
    step = ProcessStepExamples.event(
      event_store:,
      source_event: created,
      process_name: "operation-batch-runner",
      step_name: "record-item-outcome",
      subject_kind: "operation-batch-item",
      subject_id: "#{command.batch_id}:0"
    )
    expect(outcome.causation_id).to eq(step.id)
    expect(history.map(&:correlation_id).uniq).to eq([ created.correlation_id ])
    expect(history.drop(1).map { _1.metadata.fetch("command_id") }).to all(
      match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    )
    expect(skill_events.length).to eq(1)
    expect(command_events(target.command_id).map(&:type)).to eq(
      [ "CommandRegistered", "CommandSucceeded" ]
    )
  end

  it "publishes one unique multi-event registration in the shared process-manager set" do
    definition = Coordinator::Processes::Subscriptions::OperationBatchRunner::DEFINITION

    expect(definition.identity.to_h).to eq(
      set_name: "coordinator-process-managers-v1",
      subscription_name: "operation-batch-runner-v1"
    )
    expect(definition.options).to eq(
      filter: {
        streams: [ { context: "DevelopmentCoordination", stream_name: "OperationBatch" } ],
        event_types: %w[
          OperationBatchCreated
          OperationBatchContinuationRequested
          OperationBatchCancellationRequested
        ]
      }
    )
  end

  def input(**overrides)
    {
      command_id: "batch-command",
      actor: { kind: "agent", id: "agent-1" },
      batch_id: SecureRandom.uuid_v7,
      items: [ item ]
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

  def skill_events
    marker = Coordinator::Write::Skills::MarkerBuilder.new.natural_key(
      name: "review",
      scope: "project:alpha"
    )
    event_store.read_global_marked(
      Coordinator::Write::GlobalMarkedEventReadCriteria.new(
        stream_context: "AgentKnowledge",
        stream_name: "Skill",
        event_types: [ "SkillRevisionPublished" ],
        markers: [ marker ],
        maximum_count: 10,
        direction: :asc
      )
    )
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
