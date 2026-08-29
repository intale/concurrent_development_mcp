# frozen_string_literal: true

RSpec.describe Coordinator::Processes::ProcessManagers::CoordinationTaskExecutor, :event_store do
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
  let(:cancel) do
    Coordinator::Write::Operations::CancelCoordinationTask.new(transition:)
  end
  subject(:process_manager) do
    described_class.new(
      event_store:,
      task_loader: loader,
      transition:
    )
  end

  it "executes one stored target command exactly once across redelivery" do
    task_id, source = submit_task(create_change_set_command)

    first = process_manager.call(source)
    redelivery = process_manager.call(source)

    expect(first).to be_nil
    expect(redelivery).to be_nil
    expect(task_events(task_id).map(&:type)).to eq(
      [
        "CoordinationTaskSubmitted",
        "CoordinationTaskExecutionStarted",
        "CoordinationTaskCompleted"
      ]
    )
    expect(change_set_events.map(&:type)).to eq(
      [ "ChangeSetCreated", "ChangeSetAcceptanceCriteriaDefined" ]
    )
    expect(command_events.map(&:type)).to eq([ "CommandCompleted" ])

    state = loader.call(task_id).state
    expect(state.status).to eq("completed")
    expect(state.semantic_result).to have_attributes(
      kind: "success",
      command_id: "cmd-task-executor"
    )
    expect(task_events(task_id).last.metadata.fetch("schema_version")).to eq(2)
  end

  it "reconciles a working Task from its already committed target outcome" do
    command = create_change_set_command
    task_id, source = submit_task(command)
    Coordinator::Write::Operations::StartCoordinationTask.new(transition:).call(
      task_id:,
      caused_by: source
    ).value!
    started = task_events(task_id).last
    committed = Coordinator::Write::Operations::ExecuteCreateChangeSet.new(
      event_store:,
      schema_registry: schemas,
      stream_factory: streams,
      event_factory: Coordinator::Write::EventFactory.new(registry: schemas)
    ).call_command(command, caused_by: started).value!

    expect(loader.call(task_id).state.status).to eq("working")

    process_manager.call(source)

    state = loader.call(task_id).state
    completed = task_events(task_id).last
    target_completion = command_events.sole
    expect(state.status).to eq("completed")
    expect(state.semantic_result.to_h).to eq(
      Coordinator::Write::Tasks::SemanticResultMapper.new
        .call(
          Dry::Monads::Success(committed),
          command_id: command.command_id,
          tool_name: "change_set_create"
        )
        .to_h
    )
    expect(completed.causation_id).to eq(target_completion.id)
    expect(change_set_events.map(&:type)).to eq(
      [ "ChangeSetCreated", "ChangeSetAcceptanceCriteriaDefined" ]
    )
    expect(command_events.map(&:type)).to eq([ "CommandCompleted" ])
  end

  it "persists immediate causation and one correlation ID across the Saga" do
    task_id, source = submit_task(create_change_set_command)

    process_manager.call(source)

    submitted, started, completed = task_events(task_id)
    target_events = change_set_events + command_events
    completion = command_events.sole

    expect(submitted.causation_id).to be_nil
    expect(started.causation_id).to eq(submitted.id)
    expect(target_events.map(&:causation_id).uniq).to eq([ started.id ])
    expect(completed.causation_id).to eq(completion.id)
    expect(([ submitted, started, completed ] + target_events).map(&:correlation_id).uniq).to eq(
      [ submitted.correlation_id ]
    )
  end

  it "keeps an exact command replay inside the new Task Saga correlation" do
    first_task_id, first_source = submit_task(create_change_set_command)
    process_manager.call(first_source)
    replay_task_id, replay_source = submit_task(create_change_set_command)

    process_manager.call(replay_source)

    replay_submitted, replay_started, replay_completed = task_events(replay_task_id)
    expect(replay_task_id).not_to eq(first_task_id)
    expect(replay_completed.causation_id).to eq(replay_started.id)
    expect([ replay_submitted, replay_started, replay_completed ].map(&:correlation_id).uniq).to eq(
      [ replay_submitted.correlation_id ]
    )
    expect(command_events.length).to eq(1)
  end

  it "completes a domain denial as an error CallToolResult without target facts" do
    Coordinator::Write::Operations::ExecuteCreateChangeSet.new(event_store:).call_command(
      create_change_set_command(command_id: "cmd-seed-existing")
    ).value!
    task_id, source = submit_task(create_change_set_command)

    process_manager.call(source)

    submitted, started, completed = task_events(task_id)
    state = loader.call(task_id).state
    expect(state.status).to eq("completed")
    expect(state.semantic_result).to have_attributes(
      kind: "domain_rejection",
      status: "denied",
      error: have_attributes(code: "change_set_already_exists")
    )
    expect(command_events).to be_empty
    expect(completed.causation_id).to eq(started.id)
    expect([ submitted, started, completed ].map(&:correlation_id).uniq).to eq(
      [ submitted.correlation_id ]
    )
  end

  it "keeps missing Batch and ReleaseSet denials terminal across redelivery" do
    examples = [
      [ cancel_operation_batch_command, "operation_batch_not_found" ],
      [ record_release_set_verification_command, "release_set_not_found" ]
    ]

    examples.each do |command, code|
      task_id, source = submit_task(command)

      process_manager.call(source)
      process_manager.call(source)

      state = loader.call(task_id).state
      expect(state).to have_attributes(status: "completed")
      expect(state.semantic_result).to have_attributes(
        kind: "domain_rejection",
        error: have_attributes(code:)
      )
      expect(task_events(task_id).map(&:type)).to eq(
        %w[CoordinationTaskSubmitted CoordinationTaskExecutionStarted CoordinationTaskCompleted]
      )
      expect(command_events_for(command.command_id)).to be_empty
    end
  end

  it "skips a target that was cancelled before its submission is delivered" do
    task_id, source = submit_task(create_change_set_command)
    cancel.call(task_id:).value!

    expect(process_manager.call(source)).to be_nil

    submitted, cancelled = task_events(task_id)
    expect(loader.call(task_id).state.status).to eq("cancelled")
    expect(change_set_events).to be_empty
    expect(command_events).to be_empty
    expect(cancelled.causation_id).to eq(submitted.id)
    expect(cancelled.correlation_id).to eq(submitted.correlation_id)
  end

  it "handles a real filtered subscription through the shared process-manager set" do
    command = create_change_set_command
    lane_index = Coordinator::Write::Tasks::ExecutionLane.new.index(command.command_id)
    registration = Coordinator::Processes::Subscriptions::CoordinationTaskExecutor.new(
      handler: process_manager,
      lane_index:,
      pull_interval: 0.2
    )
    subscription_set = build_subscription_set([ registration ])

    begin
      subscription_set.start
      task_id, = submit_task(command)
      wait_for_subscription(subscription_set, registration.definition.subscription_name)

      expect(loader.call(task_id).state.status).to eq("completed")
      expect(change_set_events.map(&:type)).to eq(
        [ "ChangeSetCreated", "ChangeSetAcceptanceCriteriaDefined" ]
      )
    ensure
      subscription_set.stop
    end
  end

  it "publishes two unique marker-filtered subscription identities in one shared set" do
    definitions = Coordinator::Processes::Subscriptions::CoordinationTaskExecutor::LANE_COUNT.times.map do |lane|
      Coordinator::Processes::Subscriptions::CoordinationTaskExecutor.new(
        handler: process_manager,
        lane_index: lane
      ).definition
    end

    expect(definitions.map(&:subscription_name)).to eq(
      [ "coordination-task-executor-lane-0-v2", "coordination-task-executor-lane-1-v2" ]
    )
    expect(definitions.map(&:identity).uniq.length).to eq(2)
    expect(definitions.map(&:options)).to eq(
      [ 0, 1 ].map do |lane|
        {
          filter: {
            streams: [ { context: "CoordinatorControl", stream_name: "CoordinationTask" } ],
            event_types: [
              { type: "CoordinationTaskSubmitted", markers: [ "task-execution-lane:v1:#{lane}" ] }
            ]
          }
        }
      end
    )
  end

  def create_change_set_command(command_id: "cmd-task-executor")
    Coordinator::Write::Commands::CreateChangeSet.new(
      command_id:,
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "agent-a"),
      change_set_id: "CS-task-executor",
      goal: "Execute a durable coordination Task",
      acceptance_criteria: [ "Duplicate delivery creates no duplicate facts" ]
    )
  end

  def cancel_operation_batch_command
    Coordinator::Write::Commands::CancelOperationBatch.new(
      command_id: "cmd-task-executor-missing-batch",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "agent-a"),
      batch_id: "0198e03a-d112-7000-8000-000000000101"
    )
  end

  def record_release_set_verification_command
    Coordinator::Write::Operations::PrepareRecordReleaseSetVerification.new.call(
      command_id: "cmd-task-executor-missing-release-set",
      actor: { kind: "agent", id: "agent-a" },
      release_set_id: "RS-task-executor-missing",
      integration_events: [
        event_reference(
          event_id: "0198e03a-d112-7000-8000-000000000102",
          stream_id: "RS-task-executor-missing",
          stream_revision: 1
        ),
        event_reference(
          event_id: "0198e03a-d112-7000-8000-000000000103",
          stream_id: "RS-task-executor-missing",
          stream_revision: 2
        )
      ],
      evidence: {
        outcome: "passed",
        producer: { name: "coordinator-spec", version: "1" },
        run_id: "run-task-executor-missing-release-set",
        environment_digest: "sha256:#{'a' * 64}",
        result_digest: "sha256:#{'b' * 64}",
        findings: [],
        produced_at: "2026-08-27T14:00:00.000000Z"
      }
    ).value!
  end

  def event_reference(event_id:, stream_id:, stream_revision:)
    {
      event_id:,
      type: "RepositoryIntegrationRecorded",
      stream_context: "DevelopmentIntegration",
      stream_name: "ReleaseSet",
      stream_id:,
      stream_revision:
    }
  end

  def submit_task(command)
    task_id = submit.call(command).value!.task_id
    [ task_id, task_events(task_id).sole ]
  end

  def task_events(task_id)
    event_store.read(
      streams.coordination_task(task_id),
      Coordinator::Write::EventQueries::COORDINATION_TASK_HISTORY
    )
  end

  def change_set_events
    event_store.read(
      streams.change_set("CS-task-executor"),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "ChangeSetCreated", "ChangeSetAcceptanceCriteriaDefined" ],
        maximum_count: 2,
        direction: :asc
      )
    )
  end

  def command_events
    event_store.read(
      streams.command("cmd-task-executor"),
      Coordinator::Write::EventQueries::COMMAND_COMPLETION
    )
  end

  def command_events_for(command_id)
    event_store.read(
      streams.command(command_id),
      Coordinator::Write::EventQueries::COMMAND_COMPLETION
    )
  end

  def build_subscription_set(registrations)
    manager = PgEventstore.subscriptions_manager(
      subscription_set: Coordinator::Processes::Subscriptions::ProcessManagerSet::SET_NAME
    )
    Coordinator::Processes::Subscriptions::ProcessManagerSet.new(manager:, registrations:)
  end

  def wait_for_subscription(subscription_set, subscription_name)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10

    until subscription_set.processed_event_count(subscription_name) >= 1
      raise "Task subscription did not process the submission within 10 seconds" if
        Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.05
    end
  end
end
