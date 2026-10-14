# frozen_string_literal: true

RSpec.describe Coordinator::Processes::OperationBatches::ItemExecutor, :event_store do
  subject(:executor) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:loader) { Coordinator::Write::OperationBatches::Loader.new(event_store:) }
  let(:registrar) { Coordinator::Processes::OperationBatches::ItemRegistrar.new(event_store:) }
  let(:batch_executor) { Coordinator::Write::Operations::ExecuteOperationBatchCommand.new(event_store:) }
  let(:builder) { Coordinator::Processes::OperationBatches::CommandBuilder.new }
  let(:runner) { Coordinator::Processes::ProcessManagers::OperationBatchRunner.new(event_store:) }

  it "publishes a maximum-sized manifest in one stream without reading or reserving child registries" do
    command = prepare_batch(Array.new(1000) { |index| item(command_id: "request-#{index}", name: "skill-#{index}") })
    appended_streams = []
    registry_reads = []
    trace = TracePoint.new(:call) do |frame|
      next unless frame.self.equal?(event_store) && frame.defined_class == Coordinator::Write::EventStore

      appended_streams << frame.binding.local_variable_get(:reference).stream_name if frame.method_id == :append
      registry_reads << frame.method_id if %i[read_global_marked read_marked_types].include?(frame.method_id)
    end

    result = trace.enable { batch_executor.call_command(command) }

    expect(result).to be_success
    expect(appended_streams.uniq).to eq([ "OperationBatch" ])
    expect(registry_reads).to be_empty
    expect(history(command.batch_id).count { _1.type == "OperationBatchItemEnqueued" }).to eq(1000)
    expect(history(command.batch_id).first(5).map(&:type)).to eq(%w[
      OperationBatchCreated OperationBatchTargetSelected OperationBatchManifestAccepted
      OperationBatchSucceededItemsNumberChanged OperationBatchUnsuccessfulItemsNumberChanged
    ])
  ensure
    trace&.disable
  end

  it "loads only the selected item input and never hydrates manifest inputs for progress or identity decisions" do
    source = accept_batch(Array.new(8) { |index| item(command_id: "request-#{index}", name: "skill-#{index}") })
    assignment = assign(source, index: 3)
    hydrated_indexes = []
    trace = TracePoint.new(:call) do |frame|
      next unless frame.defined_class == Coordinator::Write::OperationBatches::ItemBuilder && frame.method_id == :call

      hydrated_indexes << frame.binding.local_variable_get(:payload).index
    end

    trace.enable do
      expect(loader.call(source.payload.batch_id).state).to have_attributes(item_count: 8, items: [])
      expect(loader.item_identity(source.payload.batch_id, 3).state.items.sole.command_id).to eq(assignment.item.command_id)
      expect(hydrated_indexes).to be_empty
      expect(loader.item(source.payload.batch_id, 3).state.items.sole.index).to eq(3)
    end
    expect(hydrated_indexes).to eq([ 3 ])
  ensure
    trace&.disable
  end

  it "converges concurrent batches with an identical actor request to one canonical command and one effect" do
    sources = Array.new(2) { accept_batch([ item ]) }
    ready = Queue.new
    release = Queue.new
    workers = sources.map do |source|
      Thread.new do
        ready << true
        release.pop
        Coordinator::Processes::ProcessManagers::OperationBatchRunner.new(event_store:).call(source.event)
      end
    end
    workers.length.times { ready.pop }
    workers.length.times { release << true }
    workers.each(&:value)

    assignments = sources.map { loader.item(_1.payload.batch_id, 0).state.assignment(0).command_id }
    expect(assignments.uniq.length).to eq(1)
    expect(command_history(assignments.first).map(&:type)).to eq(%w[CommandRegistered CommandSucceeded])
    sources.each do |source|
      expect(history(source.payload.batch_id).map(&:type)).to include("OperationBatchItemSucceeded", "OperationBatchCompleted")
      expect(history(source.payload.batch_id).map(&:correlation_id).uniq).to eq([ source.event.correlation_id ])
      ids = history(source.payload.batch_id).map(&:id)
      runner.call(source.event)
      expect(history(source.payload.batch_id).map(&:id)).to eq(ids)
    end
  ensure
    workers&.each(&:join)
  end

  it "records a request-reuse denial for only the conflicting item and continues other items" do
    original = accept_batch([ item ])
    runner.call(original.event)
    reused = accept_batch([
      item(instructions: "Different instructions under the same request."),
      item(command_id: "independent-request", name: "independent")
    ])

    runner.call(reused.event)
    events = history(reused.payload.batch_id)
    rejected = events.find { _1.type == "OperationBatchItemRegistrationRejected" }
    expect(rejected.data).to include("index" => 0, "error" => include("code" => "command_id_reused"))
    expect(events.count { _1.type == "OperationBatchItemCommandAssigned" }).to eq(1)
    expect(events.count { _1.type == "OperationBatchItemExecutionStarted" }).to eq(1)
    expect(loader.call(reused.payload.batch_id).state).to have_attributes(succeeded_count: 1, rejected_count: 1)
    expect(events.last.type).to eq("OperationBatchCompleted")
    expect(loader.item(reused.payload.batch_id, 0).state.assignment(0)).to be_nil
  end

  it "does not start an assigned item after cancellation and lets a later batch reuse its unexecuted binding" do
    source = accept_batch([ item ])
    assignment = assign(source)
    cancellation = cancel(source)

    result = execute(source, assignment)
    expect(result.failure.code).to eq(:operation_batch_cancellation_pending)
    runner.call(cancellation)
    expect(command_history(assignment.item.command_id).map(&:type)).to eq([ "CommandRegistered" ])
    expect(history(source.payload.batch_id).map(&:type)).not_to include("OperationBatchItemExecutionStarted")

    resubmission = accept_batch([ item ])
    runner.call(resubmission.event)
    expect(loader.item(resubmission.payload.batch_id, 0).state.assignment(0).command_id).to eq(assignment.item.command_id)
    expect(command_history(assignment.item.command_id).map(&:type)).to eq(%w[CommandRegistered CommandSucceeded])
    expect(history(resubmission.payload.batch_id).last.type).to eq("OperationBatchCompleted")
  end

  it "reconciles a committed target after cancellation even when its Batch outcome was not yet recorded" do
    source = accept_batch([ item ])
    assignment = assign(source)
    expect(execute(source, assignment)).to be_success
    before_cancel = history(source.payload.batch_id)
    expect(before_cancel.count { _1.type == "OperationBatchItemExecutionStarted" }).to eq(1)
    expect(before_cancel.map(&:type)).not_to include("OperationBatchItemSucceeded")
    cancellation = cancel(source)
    complete = Coordinator::Write::Commands::CompleteOperationBatchCancellation.new(
      command_id: SecureRandom.uuid_v7, actor: system_actor, batch_id: source.payload.batch_id
    )
    expect(batch_executor.call_command(complete, caused_by: cancellation).failure.code).to eq(:operation_batch_items_in_flight)

    runner.call(cancellation)
    runner.call(source.event)
    runner.call(cancellation)

    events = history(source.payload.batch_id)
    expect(events.count { _1.type == "OperationBatchItemExecutionStarted" }).to eq(1)
    expect(events.count { _1.type == "OperationBatchItemSucceeded" }).to eq(1)
    expect(events.count { _1.type == "OperationBatchItemCompletionLinked" }).to eq(1)
    expect(events.count { _1.type == "OperationBatchCancelled" }).to eq(1)
    expect(loader.call(source.payload.batch_id).state.pending_indexes).to be_empty
    expect(command_history(assignment.item.command_id).map(&:type)).to eq(%w[CommandRegistered CommandSucceeded])
  end

  it "validates the current canonical assignment before persisting a start or any target effect" do
    source = accept_batch([ item ])
    assignment = assign(source)
    start = builder.start_item(source:, item: assignment.item, command_id: SecureRandom.uuid_v7)
    changed = start.class.new(start.attributes.merge(item_command_id: SecureRandom.uuid_v7))

    result = executor.call(command: changed, item: assignment.item, caused_by: assignment.event)

    expect(result.failure.code).to eq(:operation_batch_item_assignment_mismatch)
    expect(history(source.payload.batch_id).map(&:type)).not_to include("OperationBatchItemExecutionStarted")
    expect(command_history(assignment.item.command_id).map(&:type)).to eq([ "CommandRegistered" ])
  end

  def prepare_batch(items)
    Coordinator::Write::Operations::PrepareCreateSkillPublishBatch.new.call({
      command_id: "cmd-batch-#{SecureRandom.uuid_v7}", actor: { kind: "agent", id: "batch-agent" },
      batch_id: SecureRandom.uuid_v7, items:
    }).value!
  end

  def accept_batch(items)
    command = prepare_batch(items)
    expect(batch_executor.call_command(command)).to be_success
    created = history(command.batch_id).find { _1.type == "OperationBatchCreated" }
    Coordinator::Processes::OperationBatches::SourceBuilder.new.call(created)
  end

  def item(**overrides)
    {
      command_id: "shared-request", actor: { kind: "agent", id: "batch-agent" },
      name: "shared-skill", scope: "project:batch-performance", expected_revision: 0,
      description: "A Skill used to verify Batch invariants.", instructions: "Inspect the complete change.", assets: []
    }.merge(overrides)
  end

  def assign(source, index: 0)
    registrar.call_command(
      builder.assign_item(source:, index:, command_id: SecureRandom.uuid_v7), caused_by: source.event
    ).value!
  end

  def execute(source, assignment)
    executor.call(
      command: builder.start_item(source:, item: assignment.item, command_id: SecureRandom.uuid_v7),
      item: assignment.item, caused_by: assignment.event
    )
  end

  def cancel(source)
    command = Coordinator::Write::Commands::CancelOperationBatch.new(
      command_id: SecureRandom.uuid_v7, actor: system_actor, batch_id: source.payload.batch_id
    )
    expect(batch_executor.call_command(command)).to be_success
    history(source.payload.batch_id).find { _1.type == "OperationBatchCancellationRequested" }
  end

  def system_actor
    Coordinator::Write::Commands::Actor.new(kind: "system", id: "batch-spec")
  end

  def history(batch_id)
    event_store.read(streams.operation_batch(batch_id), Coordinator::Write::EventQueries::OPERATION_BATCH_HISTORY)
  end

  def command_history(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_HISTORY)
  end
end
