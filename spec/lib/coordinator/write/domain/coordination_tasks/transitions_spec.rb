# frozen_string_literal: true

RSpec.describe "Coordination Task command transitions" do
  let(:task_id) { "01919191-9191-7191-8191-919191919191" }
  let(:submitted) { submission_event(task_id:) }
  let(:initial) { Coordinator::Write::Domain::CoordinationTasks::State.initial }

  it "Given an unused Task ID, when SubmitCoordinationTask runs, then it emits TaskSubmitted" do
    command = Coordinator::Write::Commands::SubmitCoordinationTask.new(submitted.to_h)

    result = Coordinator::Write::Domain::CoordinationTasks::Submit.new.call(state: initial, command:)

    expect(result).to be_success
    expect(result.value!).to eq(submitted)
  end

  it "Given a queued Task, when StartCoordinationTask runs, then it emits one start fact" do
    state = Coordinator::Write::Domain::CoordinationTasks::State.reduce([ submitted ])
    command = Coordinator::Write::Commands::StartCoordinationTask.new(
      task_id:,
      started_at: "2026-08-22T06:30:01.000000Z"
    )

    result = Coordinator::Write::Domain::CoordinationTasks::Start.new.call(state:, command:)

    expect(result.value!).to eq(
      Coordinator::Write::Events::CoordinationTaskExecutionStartedV1.new(command.to_h)
    )
  end

  it "Given an already-started Task, when Start runs again, then it emits no event" do
    state = Coordinator::Write::Domain::CoordinationTasks::State.reduce(
      [
        submitted,
        Coordinator::Write::Events::CoordinationTaskExecutionStartedV1.new(
          task_id:,
          started_at: "2026-08-22T06:30:01.000000Z"
        )
      ]
    )
    command = Coordinator::Write::Commands::StartCoordinationTask.new(
      task_id:,
      started_at: "2026-08-22T06:30:02.000000Z"
    )

    expect(Coordinator::Write::Domain::CoordinationTasks::Start.new.call(state:, command:).value!).to be_nil
  end

  it "Given a queued Task, when Cancel runs, then it immediately cancels" do
    state = Coordinator::Write::Domain::CoordinationTasks::State.reduce([ submitted ])
    command = Coordinator::Write::Commands::CancelCoordinationTask.new(
      task_id:,
      requested_at: "2026-08-22T06:30:01.000000Z"
    )

    event = Coordinator::Write::Domain::CoordinationTasks::Cancel.new.call(state:, command:).value!

    expect(event).to be_a(Coordinator::Write::Events::CoordinationTaskCancelledV1)
  end

  it "Given a running Task, when Cancel runs, then it requests cooperative cancellation" do
    state = running_state
    command = Coordinator::Write::Commands::CancelCoordinationTask.new(
      task_id:,
      requested_at: "2026-08-22T06:30:02.000000Z"
    )

    event = Coordinator::Write::Domain::CoordinationTasks::Cancel.new.call(state:, command:).value!

    expect(event).to be_a(Coordinator::Write::Events::CoordinationTaskCancellationRequestedV1)
  end

  it "Given a running Task, when a domain rejection is recorded, then it emits one semantic fact" do
    result = domain_rejection
    command = Coordinator::Write::Commands::RecordCoordinationTaskOutcome.new(
      task_id:,
      outcome: Coordinator::Write::Tasks::OutcomeV2::Completed.new(result:),
      recorded_at: "2026-08-22T06:30:02.000000Z"
    )

    event = Coordinator::Write::Domain::CoordinationTasks::RecordOutcome.new.call(
      state: running_state,
      command:
    ).value!

    expect(event).to be_a(Coordinator::Write::Events::CoordinationTaskCompletedV2)
    expect(event.result).to have_attributes(
      kind: "domain_rejection",
      status: "denied",
      error: have_attributes(code: "change_set_already_exists")
    )
  end

  it "Given a running Task, when a JSON-RPC failure is recorded, then it emits TaskFailed" do
    command = Coordinator::Write::Commands::RecordCoordinationTaskOutcome.new(
      task_id:,
      outcome: Coordinator::Write::Tasks::OutcomeV2::Failed.new(
        error: Coordinator::Write::Tasks::JsonRpcErrorV1.new(code: -32_603, message: "Internal error")
      ),
      recorded_at: "2026-08-22T06:30:02.000000Z"
    )

    event = Coordinator::Write::Domain::CoordinationTasks::RecordOutcome.new.call(
      state: running_state,
      command:
    ).value!

    expect(event).to be_a(Coordinator::Write::Events::CoordinationTaskFailedV1)
  end

  def running_state
    Coordinator::Write::Domain::CoordinationTasks::State.reduce(
      [
        submitted,
        Coordinator::Write::Events::CoordinationTaskExecutionStartedV1.new(
          task_id:,
          started_at: "2026-08-22T06:30:01.000000Z"
        )
      ]
    )
  end

  def submission_event(task_id:)
    command = target_command
    digest = Coordinator::Write::CommandInputDigest.new

    Coordinator::Write::Events::CoordinationTaskSubmittedV2.new(
      task_id:,
      tool_name: "change_set_create",
      command_id: command.command_id,
      command_input: digest.document(command),
      submitted_at: "2026-08-22T06:30:00.000000Z",
      ttl_ms: nil,
      poll_interval_ms: 500
    )
  end

  def target_command
    Coordinator::Write::Commands::CreateChangeSet.new(
      command_id: "cmd-task-101",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "agent-a"),
      change_set_id: "CS-101",
      goal: "Coordinate billing changes",
      acceptance_criteria: [ "Every target command is durable" ]
    )
  end

  def domain_rejection
    error = Coordinator::Write::Tasks::DomainErrorV1::ChangeSetError.new(
      code: "change_set_already_exists",
      message: "ChangeSet already exists",
      details: Coordinator::Write::Tasks::DomainErrorV1::ChangeSetDetails.new(
        change_set_id: "CS-101"
      )
    )
    Coordinator::Write::Tasks::SemanticResultV1::DomainRejection.new(
      kind: "domain_rejection",
      status: "denied",
      summary: error.message,
      command_id: "cmd-task-101",
      error:,
      next_actions: []
    )
  end
end
