# frozen_string_literal: true

RSpec.describe Coordinator::Processes::OperationBatches::TaskCompleter, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }

  it "settles the original Task from terminal Batch facts and converges on redelivery" do
    command = Coordinator::Write::Operations::PrepareCreateSkillPublishBatch.new.call(
      command_id: "batch-task-root", actor: { kind: "agent", id: "receipt-agent" },
      batch_id: SecureRandom.uuid_v7,
      items: [ { command_id: "batch-child", actor: { kind: "agent", id: "receipt-agent" },
        name: "receipt-skill", scope: "project:receipt", expected_revision: 0,
        description: "Receipt example", instructions: "Use authoritative outcomes.", assets: [] } ]
    ).value!
    task = Coordinator::Write::Operations::SubmitCoordinationTask.new(event_store:).call(command).value!
    submitted = event_store.read(streams.coordination_task(task.task_id), Coordinator::Write::EventQueries::COORDINATION_TASK_HISTORY).first
    Coordinator::Processes::ProcessManagers::CoordinationTaskExecutor.new(event_store:).call(submitted)
    Coordinator::Processes::ProcessManagers::CoordinationTaskExecutor.new(event_store:).call(submitted)
    expect(Coordinator::Write::Tasks::Loader.new(event_store:).call(task.task_id).state.status).to eq("working")
    expect(Coordinator::Write::CommandLifecycle::Loader.new(event_store:).call(task.command_id).state.status).to eq("registered")
    created = event_store.read_grouped(streams.operation_batch(command.batch_id), Coordinator::Write::EventQueries::OPERATION_BATCH_CONTROL)
      .find { _1.type == "OperationBatchCreated" }
    Coordinator::Processes::ProcessManagers::OperationBatchRunner.new(event_store:).call(created)
    terminal = event_store.read_grouped(streams.operation_batch(command.batch_id), Coordinator::Write::EventQueries::OPERATION_BATCH_CONTROL)
      .find { _1.type == "OperationBatchCompleted" }
    child = Coordinator::Write::OperationBatches::Loader.new(event_store:).item(command.batch_id, 0).state.item(0)
    child_terminal = event_store.read(streams.command(child.command_id), Coordinator::Write::EventQueries::COMMAND_HISTORY).last
    expect(Coordinator::Write::CommandResults::SourceLoader.new(event_store:).call(child_terminal)).not_to be_nil

    described_class.new(event_store:).call(terminal)
    completed = Coordinator::Write::Tasks::Loader.new(event_store:).call(task.task_id)
    expect(completed.state.status).to eq("completed")
    result = Coordinator::Write::Tasks::ResultResolver.new(event_store:).call(completed.state)
    expect(result.data).to have_attributes(succeeded: 1, rejected: 0, failed: 0, not_run: 0)
    expect(result.completion).to have_attributes(scope: "saga", outcome: "succeeded", effects: "committed")
    described_class.new(event_store:).call(terminal)
    expect(Coordinator::Write::Tasks::Loader.new(event_store:).call(task.task_id).latest_revision).to eq(completed.latest_revision)
  end

  it "settles a cancellation initiated under a different correlation without inventing target effects" do
    task, terminal = cancelled_batch
    submitted = task_events(task.task_id).first
    expect(terminal.correlation_id).not_to eq(submitted.correlation_id)

    described_class.new(event_store:).call(terminal)
    state = Coordinator::Write::Tasks::Loader.new(event_store:).call(task.task_id).state
    result = Coordinator::Write::Tasks::ResultResolver.new(event_store:).call(state)
    expect(result.error.details).to have_attributes(succeeded: 0, rejected: 0, failed: 0, not_run: 1)
    expect(result.completion).to have_attributes(scope: "saga", outcome: "cancelled", effects: "none")
  end

  it "recovers the independent commit gap between command finalization and Task finalization" do
    task, terminal = cancelled_batch
    armed = true
    trace = TracePoint.new(:call) do |frame|
      next unless armed && frame.defined_class == Coordinator::Write::Operations::RecordCoordinationTaskOutcome && frame.method_id == :call
      armed = false
      raise "Interrupted before Task completion"
    end
    expect { trace.enable { described_class.new(event_store:).call(terminal) } }.to raise_error(RuntimeError, "Interrupted before Task completion")
    canonical = Coordinator::Write::CommandLifecycle::Loader.new(event_store:).call(task.command_id)
    expect(canonical.state).to be_succeeded
    expect(task_events(task.task_id).map(&:type)).not_to include("CoordinationTaskCompleted")

    described_class.new(event_store:).call(terminal)
    described_class.new(event_store:).call(terminal)
    expect(task_events(task.task_id).count { _1.type == "CoordinationTaskCompleted" }).to eq(1)
    expect(Coordinator::Write::CommandLifecycle::Loader.new(event_store:).call(task.command_id).persisted_events.map(&:id)).to eq(canonical.persisted_events.map(&:id))
  ensure
    trace&.disable
  end

  it "reports exhausted item execution as failed rather than a business rejection" do
    task, command, creation = accepted_batch
    failure = Coordinator::Write::Tasks::ExecutionFailureV1.new(failed_step: "assign-item",
      reason_code: "concurrency_conflict", reason: "Three attempts exhausted; retry may succeed",
      retryable: true, effects_committed: false, attempts: 3)
    Coordinator::Write::Operations::ExecuteRecordOperationBatchItemFailure.new(event_store:).call_command(
      Coordinator::Write::Commands::RecordOperationBatchItemFailure.new(command_id: SecureRandom.uuid_v7,
        actor: command.actor, batch_id: command.batch_id, index: 0, failure:), caused_by: creation).value!
    completion = Coordinator::Write::Operations::ExecuteOperationBatchCommand.new(event_store:).call_command(
      Coordinator::Write::Commands::CompleteOperationBatch.new(command_id: SecureRandom.uuid_v7,
        actor: command.actor, batch_id: command.batch_id), caused_by: creation).value!
    described_class.new(event_store:).call(completion.terminal_event)
    state = Coordinator::Write::Tasks::Loader.new(event_store:).call(task.task_id).state
    result = Coordinator::Write::Tasks::ResultResolver.new(event_store:).call(state)
    expect(result.error.details).to have_attributes(succeeded: 0, rejected: 0, failed: 1, not_run: 0)
    expect(result.completion).to have_attributes(outcome: "partial_failure", effects: "none")
  end

  def accepted_batch
    command = Coordinator::Write::Operations::PrepareCreateSkillPublishBatch.new.call(
      command_id: "fixture-batch-task", actor: { kind: "agent", id: "receipt-agent" }, batch_id: SecureRandom.uuid_v7,
      items: [ { command_id: "fixture-child", actor: { kind: "agent", id: "receipt-agent" },
        name: "fixture-skill", scope: "project:receipt", expected_revision: 0,
        description: "Receipt example", instructions: "Use authoritative outcomes.", assets: [] } ]).value!
    task = Coordinator::Write::Operations::SubmitCoordinationTask.new(event_store:).call(command).value!
    submitted = task_events(task.task_id).first
    payload = Coordinator::Write::EventSchemaRegistry.new.load(type: submitted.type,
      schema_version: submitted.metadata.fetch("schema_version"), data: submitted.data)
    canonical = Coordinator::Write::Tasks::TargetCommandBuilder.new.call(payload.command_input)
    Coordinator::Write::Operations::StartCoordinationTask.new(
      transition: Coordinator::Write::Operations::ApplyCoordinationTaskTransition.new(event_store:)
    ).call(task_id: task.task_id, caused_by: submitted).value!
    created = Coordinator::Write::Operations::ExecuteOperationBatchCommand.new(event_store:).call_command(canonical, caused_by: submitted).value!
    [ task, canonical, created.emitted_events.first.then { event_store.read_at(streams.operation_batch(command.batch_id), _1.stream_revision) } ]
  end

  def cancelled_batch
    task, command, = accepted_batch
    executor = Coordinator::Write::Operations::ExecuteOperationBatchCommand.new(event_store:)
    requested = executor.call_command(Coordinator::Write::Commands::CancelOperationBatch.new(command_id: "fixture-cancel",
      actor: command.actor, batch_id: command.batch_id)).value!
    cancelled = executor.call_command(Coordinator::Write::Commands::CompleteOperationBatchCancellation.new(command_id: SecureRandom.uuid_v7,
      actor: command.actor, batch_id: command.batch_id), caused_by: requested.terminal_event).value!
    [ task, cancelled.terminal_event ]
  end

  def task_events(task_id)
    event_store.read(streams.coordination_task(task_id), Coordinator::Write::EventQueries::COORDINATION_TASK_HISTORY)
  end
end
