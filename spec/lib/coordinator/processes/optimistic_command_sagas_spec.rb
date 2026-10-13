# frozen_string_literal: true

RSpec.describe Coordinator::Processes::TargetCommandExecutor, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:submit) { Coordinator::Write::Operations::SubmitCoordinationTask.new(event_store:) }
  let(:executor) { described_class.new(event_store:) }

  it "recovers an atomic target committed before its canonical completion without dispatching it again" do
    target, parent = submit_target
    completion = Coordinator::Write::Operations::ExecuteCreateChangeSet.new(event_store:).call_command(target, caused_by: parent).value!
    dispatches = []
    trace = TracePoint.new(:call) do |frame|
      dispatches << true if frame.defined_class == Coordinator::Write::Operations::ExecuteCreateChangeSet && frame.method_id == :call_command
    end
    execution = trace.enable { executor.call(target, caused_by: parent).value! }
    expect(dispatches).to be_empty
    expect(execution.command_state).to be_succeeded
    expect(execution.terminal_event.causation_id).to eq(completion.terminal_event.id)
    expect(history(target).map(&:type)).to eq(%w[CommandRegistered CommandSucceeded])
    expect(executor.call(target, caused_by: parent).value!.terminal_event.id).to eq(execution.terminal_event.id)
  ensure
    trace&.disable
  end

  it "converges competing terminal recorders on one optimistic winner" do
    target, parent = submit_target
    Coordinator::Write::Operations::ExecuteCreateChangeSet.new(event_store:).call_command(target, caused_by: parent).value!
    ready = Queue.new
    release = Queue.new
    workers = Array.new(2) do
      Thread.new do
        ready << true
        release.pop
        described_class.new(event_store:).call(target, caused_by: parent).value!
      end
    end
    2.times { ready.pop }
    2.times { release << true }
    outcomes = workers.map(&:value)
    expect(outcomes.map { _1.terminal_event.id }.uniq.length).to eq(1)
    expect(history(target).map(&:type)).to eq(%w[CommandRegistered CommandSucceeded])
  ensure
    workers&.each(&:join)
  end

  it "exhausts exactly three real wrong-revision races, without a serializable transaction" do
    target, = submit_target
    stream = PgEventstore::Stream.new(**streams.change_set(target.change_set_id).to_h)
    client = PgEventstore.client
    attempts = 0
    revision_retry = Coordinator::Write::Operations::OptimisticRevisionRetry.new
    expect do
      revision_retry.call do
        revision = attempts.zero? ? :no_stream : attempts - 1
        client.append_to_stream(stream, [ PgEventstore::Event.new(type: "RevisionRaceWon", data: {}) ])
        attempts += 1
        client.append_to_stream(stream, [ PgEventstore::Event.new(type: "RevisionRaceLost", data: {}) ], options: { expected_revision: revision })
      end
    end.to raise_error(PgEventstore::WrongExpectedRevisionError)
    expect(attempts).to eq(3)
  end

  it "projects an execution failure as a typed error with the real committed effect references" do
    target, parent = submit_target
    completion = Coordinator::Write::Operations::ExecuteCreateChangeSet.new(event_store:).call_command(target, caused_by: parent).value!
    failure = Coordinator::Write::Tasks::ExecutionFailureV1.new(
      failed_step: "later-step", reason_code: "concurrency_conflict",
      reason: "Concurrent changes exhausted three attempts; this request may succeed if retried",
      retryable: true, effects_committed: true, attempts: 3
    )
    transition = Coordinator::Write::Operations::ApplyCommandTransition.new(event_store:).call(
      command: Coordinator::Write::Commands::FailCommand.new(command_id: target.command_id, failure:),
      decider: Coordinator::Write::Domain::CommandLifecycles::Fail.new,
      actor: target.actor, tool_name: "change_set_create", caused_by: completion.terminal_event
    ).value!
    source = Coordinator::Write::CommandResults::SourceLoader.new(event_store:).call(transition.terminal_event)
    result = Coordinator::Write::CommandResults::Assembler.new(event_store:).call(source)
    expect(result.status).to eq("failed")
    expect(result.data.code).to eq("saga_execution_failed")
    expect(result.data.details).to have_attributes(effects_committed: true, attempts: 3, retryable: true)
    expect(result.emitted_events.map(&:type)).to eq(%w[ChangeSetCreated ChangeSetGoalDefined ChangeSetAcceptanceCriteriaDefined])
    expect(executor.call(target, caused_by: parent).value!.command_state).to be_failed
  end

  def submit_target
    input = Coordinator::Write::Commands::CreateChangeSet.new(
      command_id: "optimistic-saga-test", actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "agent-a"),
      change_set_id: "optimistic-saga-CS", goal: "Recover independent commits",
      acceptance_criteria: [ "Interrupted deliveries converge" ]
    )
    task = submit.call(input).value!
    parent = event_store.read(streams.coordination_task(task.task_id), Coordinator::Write::EventQueries::COORDINATION_TASK_HISTORY).first
    payload = Coordinator::Write::EventSchemaRegistry.new.load(type: parent.type, schema_version: parent.metadata.fetch("schema_version"), data: parent.data)
    [ Coordinator::Write::Tasks::TargetCommandBuilder.new.call(payload.command_input), parent ]
  end

  def history(target)
    event_store.read(streams.command(target.command_id), Coordinator::Write::EventQueries::COMMAND_HISTORY)
  end
end
