# frozen_string_literal: true

RSpec.describe "Coordination Task lifecycle operations", :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:schemas) { Coordinator::Write::EventSchemaRegistry.new }
  let(:loader) do
    Coordinator::Write::Tasks::Loader.new(
      event_store:,
      stream_factory: streams,
      schema_registry: schemas
    )
  end
  let(:transition) do
    Coordinator::Write::Operations::ApplyCoordinationTaskTransition.new(
      event_store:,
      loader:,
      stream_factory: streams,
      event_factory: Coordinator::Write::EventFactory.new(registry: schemas)
    )
  end
  let(:submit) do
    Coordinator::Write::Operations::SubmitCoordinationTask.new(
      event_store:,
      stream_factory: streams,
      event_factory: Coordinator::Write::EventFactory.new(registry: schemas)
    )
  end
  let(:start) { Coordinator::Write::Operations::StartCoordinationTask.new(transition:) }
  let(:cancel) { Coordinator::Write::Operations::CancelCoordinationTask.new(transition:) }
  let(:record_outcome) do
    Coordinator::Write::Operations::RecordCoordinationTaskOutcome.new(transition:)
  end
  let(:get_task) { Coordinator::Write::Operations::GetCoordinationTask.new(loader:) }
  let(:acknowledge_input) do
    Coordinator::Write::Operations::AcknowledgeTaskInput.new(loader:)
  end
  let(:target_command) do
    Coordinator::Write::Commands::CreateChangeSet.new(
      command_id: "cmd-task-201",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "agent-a"),
      change_set_id: "CS-task-201",
      goal: "Coordinate a durable task",
      acceptance_criteria: [ "The Task can be resumed by its bearer handle" ]
    )
  end

  it "submits an immediately resolvable Task with stable routing markers" do
    result = submit.call(target_command)

    expect(result).to be_success
    state = result.value!
    expect(state.status).to eq("working")
    expect(state.task_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(get_task.call(task_id: state.task_id).value!).to eq(state)

    event = task_events(state.task_id).sole
    expect(event.type).to eq("CoordinationTaskSubmitted")
    expect(event.metadata.fetch("schema_version")).to eq(2)
    expect(event.data).not_to have_key("canonical_input_digest")
    expect(event.markers).to eq(
      [
        "command:cmd-task-201",
        Coordinator::Write::Tasks::ExecutionLane.new.marker(target_command.command_id),
        "task:#{state.task_id}",
        "tool:change_set_create"
      ]
    )
  end

  it "serializes simultaneous starts into one start fact and successful rereads" do
    task_id = submit.call(target_command).value!.task_id

    results = 4.times.map do
      Thread.new do
        local_transition = Coordinator::Write::Operations::ApplyCoordinationTaskTransition.new(
          event_store:,
          loader:,
          stream_factory: streams,
          event_factory: Coordinator::Write::EventFactory.new(registry: schemas)
        )
        Coordinator::Write::Operations::StartCoordinationTask.new(
          transition: local_transition
        ).call(task_id:)
      end
    end.map(&:value)

    expect(results).to all(
      satisfy do |result|
        result.success? || result.failure.code == :concurrency_conflict
      end
    )
    expect(task_events(task_id).map(&:type)).to eq(
      [ "CoordinationTaskSubmitted", "CoordinationTaskExecutionStarted" ]
    )
  end

  it "cancels a queued Task and never creates a start fact afterward" do
    task_id = submit.call(target_command).value!.task_id

    expect(cancel.call(task_id:)).to be_success
    expect(start.call(task_id:)).to be_success

    state = get_task.call(task_id:).value!
    expect(state.status).to eq("cancelled")
    expect(task_events(task_id).map(&:type)).to eq(
      [ "CoordinationTaskSubmitted", "CoordinationTaskCancelled" ]
    )
  end

  it "keeps running cancellation cooperative and permits a later tool completion" do
    task_id = submit.call(target_command).value!.task_id
    start.call(task_id:).value!
    cancel.call(task_id:).value!

    result = domain_rejection
    outcome = Coordinator::Write::Tasks::OutcomeV2::Completed.new(result:)
    completed = record_outcome.call(task_id:, outcome:)

    expect(completed).to be_success
    expect(completed.value!.status).to eq("completed")
    expect(completed.value!.semantic_result).to eq(result)
    expect(get_task.call(task_id:).value!.semantic_result).to eq(result)
    expect(acknowledge_input.call(task_id:)).to be_success
    expect(task_events(task_id).map(&:type)).to eq(
      [
        "CoordinationTaskSubmitted",
        "CoordinationTaskExecutionStarted",
        "CoordinationTaskCancellationRequested",
        "CoordinationTaskCompleted"
      ]
    )
  end

  it "persists a JSON-RPC execution fault as failed rather than as a tool result" do
    task_id = submit.call(target_command).value!.task_id
    start.call(task_id:).value!
    error = Coordinator::Write::Tasks::JsonRpcErrorV1.new(
      code: -32_603,
      message: "Internal error"
    )

    result = record_outcome.call(
      task_id:,
      outcome: Coordinator::Write::Tasks::OutcomeV2::Failed.new(error:)
    )

    expect(result).to be_success
    persisted = get_task.call(task_id:).value!
    expect(persisted.status).to eq("failed")
    expect(persisted.error).to eq(error)
    expect(persisted.semantic_result).to be_nil
  end

  it "returns task-not-found without appending for get, update, and cancel" do
    unknown_id = "02919191-9191-7191-8191-919191919191"

    results = [
      get_task.call(task_id: unknown_id),
      acknowledge_input.call(task_id: unknown_id),
      cancel.call(task_id: unknown_id)
    ]

    expect(results).to all(be_failure)
    expect(results.map { _1.failure.code }.uniq).to eq([ :task_not_found ])
    expect(task_events(unknown_id)).to be_empty
  end

  def task_events(task_id)
    event_store.read(
      streams.coordination_task(task_id),
      Coordinator::Write::EventQueries::COORDINATION_TASK_HISTORY
    )
  end

  def domain_rejection
    error = Coordinator::Write::Tasks::DomainErrorV1::ChangeSetError.new(
      code: "change_set_already_exists",
      message: "ChangeSet already exists",
      details: Coordinator::Write::Tasks::DomainErrorV1::ChangeSetDetails.new(
        change_set_id: target_command.change_set_id
      )
    )

    Coordinator::Write::Tasks::SemanticResultV1::DomainRejection.new(
      kind: "domain_rejection",
      status: "denied",
      summary: error.message,
      command_id: target_command.command_id,
      error:,
      next_actions: []
    )
  end
end
