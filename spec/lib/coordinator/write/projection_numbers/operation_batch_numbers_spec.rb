# frozen_string_literal: true

RSpec.describe "OperationBatch absolute numbers", :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:loader) { Coordinator::Write::OperationBatches::Loader.new(event_store:) }
  let(:actor) { Coordinator::Write::Commands::Actor.new(kind: "system", id: "numbers-spec") }

  it "uses latest number facts with only the selected item's bounded source slice" do
    command, source = accept_batch(3)
    record_failure(command, source, index: 0)
    reads = []
    trace = TracePoint.new(:call) do |frame|
      next unless frame.self.equal?(event_store) && frame.method_id == :read

      reads << frame.binding.local_variable_get(:criteria).event_types
    end
    snapshot = trace.enable { loader.item(command.batch_id, 1) }

    expect(snapshot.state).to have_attributes(succeeded_items_number: 0, unsuccessful_items_number: 1)
    expect(snapshot.state.items.map(&:index)).to eq([ 1 ])
    expect(snapshot.state.outcomes).to be_empty
    expect(reads).not_to include(Coordinator::Write::EventQueries::OPERATION_BATCH_PROGRESS.event_types)
  ensure
    trace&.disable
  end

  it "atomically records a failure and its absolute number, and does not increment on redelivery" do
    command, source = accept_batch(2)
    failure = failure_command(command, index: 0)
    operation = Coordinator::Write::Operations::ExecuteRecordOperationBatchItemFailure.new(event_store:)

    expect(operation.call_command(failure, caused_by: source)).to be_success
    before = history(command).map(&:id)
    expect(operation.call_command(failure, caused_by: source)).to be_success

    expect(history(command).map(&:id)).to eq(before)
    expect(history(command).last(2).map(&:type)).to eq([
      "OperationBatchItemFailed", "OperationBatchUnsuccessfulItemsNumberChanged"
    ])
    expect(history(command).last.data).to eq("batch_id" => command.batch_id, "items_number" => 1)
    expect(history(command).last.causation_id).to eq(source.id)
    expect(history(command).last.correlation_id).to eq(source.correlation_id)
  end

  it "serializes concurrent different-item failures into the correct absolute number" do
    command, source = accept_batch(2)
    ready = Queue.new
    release = Queue.new
    workers = 2.times.map do |index|
      Thread.new do
        ready << true
        release.pop
        operation = Coordinator::Write::Operations::ExecuteRecordOperationBatchItemFailure.new(event_store:)
        operation.call_command(failure_command(command, index:), caused_by: source)
      end
    end
    workers.length.times { ready.pop }
    workers.length.times { release << true }

    expect(workers.map(&:value)).to all(be_success)
    numbers = history(command).select { _1.type == "OperationBatchUnsuccessfulItemsNumberChanged" }
    expect(numbers.map { _1.data.fetch("items_number") }).to eq([ 0, 1, 2 ])
    expect(loader.item(command.batch_id, 0).state.unsuccessful_items_number).to eq(2)
  ensure
    workers&.each(&:join)
  end

  it "assigns numbers for accepted effects once when a complete source is replayed" do
    command, source = accept_batch(3)
    manager = Coordinator::Processes::ProcessManagers::OperationBatchRunner.new(event_store:)
    manager.call(source)
    before = history(command).map(&:id)
    manager.call(source)

    expect(history(command).map(&:id)).to eq(before)
    numbers = history(command).select { _1.type == "OperationBatchSucceededItemsNumberChanged" }
    expect(numbers.map { _1.data.fetch("items_number") }).to eq([ 0, 1, 2, 3 ])
    expect(loader.item_identity(command.batch_id, 2).state).to have_attributes(
      succeeded_items_number: 3, unsuccessful_items_number: 0
    )
  end

  def accept_batch(count)
    input = {
      command_id: "numbers-batch-#{SecureRandom.uuid_v7}", actor: { kind: "agent", id: "numbers-agent" },
      batch_id: SecureRandom.uuid_v7,
      items: Array.new(count) do |index|
        { command_id: "number-item-#{index}", actor: { kind: "agent", id: "numbers-agent" },
          name: "number-skill-#{index}", scope: "project:numbers", expected_revision: 0,
          description: "Counted publication", instructions: "Passive instructions", assets: [] }
      end
    }
    command = Coordinator::Write::Operations::PrepareCreateSkillPublishBatch.new.call(input).value!
    result = Coordinator::Write::Operations::ExecuteOperationBatchCommand.new(event_store:).call_command(command)
    expect(result).to be_success
    [ command, history(command).find { _1.type == "OperationBatchCreated" } ]
  end

  def record_failure(command, source, index:)
    operation = Coordinator::Write::Operations::ExecuteRecordOperationBatchItemFailure.new(event_store:)
    expect(operation.call_command(failure_command(command, index:), caused_by: source)).to be_success
  end

  def failure_command(command, index:)
    Coordinator::Write::Commands::RecordOperationBatchItemFailure.new(
      command_id: SecureRandom.uuid_v7, actor:, batch_id: command.batch_id, index:,
      failure: Coordinator::Write::Tasks::ExecutionFailureV1.new(
        failed_step: "execute-target", reason_code: "concurrency_conflict",
        reason: "A later request may succeed", retryable: true, effects_committed: false, attempts: 3
      )
    )
  end

  def history(command)
    event_store.read(streams.operation_batch(command.batch_id), Coordinator::Write::EventQueries::OPERATION_BATCH_HISTORY)
  end
end
