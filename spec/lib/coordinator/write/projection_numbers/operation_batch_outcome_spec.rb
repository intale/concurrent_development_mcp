# frozen_string_literal: true

RSpec.describe "Explicit Batch terminal outcomes", :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:actor) { Coordinator::Write::Commands::Actor.new(kind: "system", id: "batch-outcome-spec") }
  let(:operation) { Coordinator::Write::Operations::ExecuteOperationBatchCommand.new(event_store:) }

  it "records completed independently of any Read row for an all-success Batch" do
    command, source = accept_batch
    Coordinator::Processes::ProcessManagers::OperationBatchRunner.new(event_store:).call(source)
    facts = history(command.batch_id)
    expect(facts.last(2).map(&:type)).to eq(%w[OperationBatchOutcomeRecorded OperationBatchCompleted])
    expect(facts[-2].data).to eq("batch_id" => command.batch_id, "outcome" => "completed")
    expect(facts.last.data).to eq("batch_id" => command.batch_id)
    expect(facts.last(2).map(&:causation_id).uniq.length).to eq(1)
    expect(facts.last(2).map(&:correlation_id)).to eq([ source.correlation_id, source.correlation_id ])
  end

  it "records completed_with_errors atomically with completion from an authoritative unsuccessful outcome" do
    command, source = accept_batch
    failure = Coordinator::Write::Commands::RecordOperationBatchItemFailure.new(
      command_id: SecureRandom.uuid_v7, actor:, batch_id: command.batch_id, index: 0,
      failure: Coordinator::Write::Tasks::ExecutionFailureV1.new(
        failed_step: "execute-target", reason_code: "concurrency_conflict", reason: "A later retry may succeed",
        retryable: true, effects_committed: false, attempts: 3))
    expect(Coordinator::Write::Operations::ExecuteRecordOperationBatchItemFailure.new(event_store:)
      .call_command(failure, caused_by: source)).to be_success
    result = operation.call_command(complete_command(command.batch_id), caused_by: source)
    expect(result).to be_success
    expect(result.value!.data.transition).to eq("completed")
    facts = history(command.batch_id).last(2)
    expect(facts.map(&:type)).to eq(%w[OperationBatchOutcomeRecorded OperationBatchCompleted])
    expect(facts.first.data).to include("outcome" => "completed_with_errors")
    expect(facts.map(&:causation_id)).to eq([ source.id, source.id ])
    expect(facts.map { _1.metadata.fetch("command_id") }.uniq.length).to eq(1)
  end

  it "records cancelled with its terminal fact without starting the remaining item" do
    command, source = accept_batch
    cancellation = Coordinator::Write::Commands::CancelOperationBatch.new(
      command_id: SecureRandom.uuid_v7, actor:, batch_id: command.batch_id)
    cancelled = operation.call_command(cancellation, caused_by: source).value!.emitted_events.last
    parent = event_store.read_at(streams.operation_batch(command.batch_id), cancelled.stream_revision)
    result = operation.call_command(Coordinator::Write::Commands::CompleteOperationBatchCancellation.new(
      command_id: SecureRandom.uuid_v7, actor:, batch_id: command.batch_id), caused_by: parent)
    expect(result).to be_success
    expect(result.value!.data.transition).to eq("cancelled")
    facts = history(command.batch_id).last(2)
    expect(facts.map(&:type)).to eq(%w[OperationBatchOutcomeRecorded OperationBatchCancelled])
    expect(facts.first.data).to eq("batch_id" => command.batch_id, "outcome" => "cancelled")
    expect(facts.map(&:causation_id)).to eq([ parent.id, parent.id ])
    expect(history(command.batch_id).map(&:type)).not_to include("OperationBatchItemExecutionStarted")
  end

  it "leaves pending and non-cancelled Batches without any terminal outcome fact" do
    command, source = accept_batch
    before = history(command.batch_id).map(&:id)
    pending = operation.call_command(complete_command(command.batch_id), caused_by: source)
    cancellation = operation.call_command(Coordinator::Write::Commands::CompleteOperationBatchCancellation.new(
      command_id: SecureRandom.uuid_v7, actor:, batch_id: command.batch_id), caused_by: source)
    expect(pending.failure.code).to eq(:operation_batch_items_pending)
    expect(cancellation.failure.code).to eq(:operation_batch_cancellation_not_requested)
    expect(history(command.batch_id).map(&:id)).to eq(before)
  end

  def accept_batch
    command = Coordinator::Write::Operations::PrepareCreateSkillPublishBatch.new.call(
      command_id: "batch-outcome-#{SecureRandom.uuid_v7}", actor: { kind: "agent", id: "batch-outcome-agent" },
      batch_id: SecureRandom.uuid_v7, items: [
        { command_id: "batch-outcome-item", actor: { kind: "agent", id: "batch-outcome-agent" },
          name: "batch-outcome-skill", scope: "project:batch-outcome", expected_revision: 0,
          description: "Terminal outcome example", instructions: "Passive instructions", assets: [] }
      ]).value!
    expect(operation.call_command(command)).to be_success
    [ command, history(command.batch_id).first ]
  end

  def complete_command(batch_id)
    Coordinator::Write::Commands::CompleteOperationBatch.new(command_id: SecureRandom.uuid_v7, actor:, batch_id:)
  end

  def history(batch_id)
    event_store.read(streams.operation_batch(batch_id), Coordinator::Write::EventQueries::OPERATION_BATCH_HISTORY)
  end
end
