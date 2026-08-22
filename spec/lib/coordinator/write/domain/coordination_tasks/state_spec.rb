# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::CoordinationTasks::State do
  let(:task_id) { "A" * 43 }
  let(:submitted) { task_submitted(task_id:) }

  it "folds a completed Task from its bounded authoritative history" do
    started = Coordinator::Write::Events::CoordinationTaskExecutionStartedV1.new(
      task_id:,
      started_at: "2026-08-22T06:30:01.000000Z"
    )
    completed = Coordinator::Write::Events::CoordinationTaskCompletedV1.new(
      task_id:,
      result: successful_result,
      completed_at: "2026-08-22T06:30:02.000000Z"
    )

    state = described_class.reduce([ submitted, started, completed ])

    expect(state.status).to eq("completed")
    expect(state.started).to be(true)
    expect(state.result).to eq(successful_result)
    expect(state.last_updated_at).to eq("2026-08-22T06:30:02.000000Z")
  end

  it "retains availability while cooperative cancellation is outstanding" do
    state = described_class.reduce(
      [
        submitted,
        Coordinator::Write::Events::CoordinationTaskExecutionStartedV1.new(
          task_id:,
          started_at: "2026-08-22T06:30:01.000000Z"
        ),
        Coordinator::Write::Events::CoordinationTaskCancellationRequestedV1.new(
          task_id:,
          requested_at: "2026-08-22T06:30:02.000000Z"
        )
      ]
    )

    expect(state.status).to eq("working")
    expect(state.cancellation_requested).to be(true)
    expect(state.status_message).to match(/Cancellation requested/)
  end

  it "rejects a terminal outcome before execution starts" do
    completed = Coordinator::Write::Events::CoordinationTaskCompletedV1.new(
      task_id:,
      result: successful_result,
      completed_at: "2026-08-22T06:30:02.000000Z"
    )

    expect do
      described_class.reduce([ submitted, completed ])
    end.to raise_error(Coordinator::Write::InvalidCoordinationTaskHistory)
  end

  def task_submitted(task_id:)
    command = Coordinator::Write::Commands::CreateChangeSet.new(
      command_id: "cmd-task-101",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "agent-a"),
      change_set_id: "CS-101",
      goal: "Coordinate billing changes",
      acceptance_criteria: [ "Every target command is durable" ]
    )
    digest = Coordinator::Write::CommandInputDigest.new

    Coordinator::Write::Events::CoordinationTaskSubmittedV1.new(
      task_id:,
      tool_name: "change_set_create",
      command_id: command.command_id,
      canonical_input_digest: digest.call(command),
      command_input: digest.document(command),
      submitted_at: "2026-08-22T06:30:00.000000Z",
      ttl_ms: nil,
      poll_interval_ms: 500
    )
  end

  def successful_result
    @successful_result ||= Coordinator::Write::Tasks::ToolResultV1.new(
      content: [
        Coordinator::Write::Tasks::TextContentV1.new(type: "text", text: "ChangeSet created")
      ],
      is_error: false,
      structured_content: Coordinator::Write::Tasks::StructuredContentV1.new(
        status: "ok",
        summary: "ChangeSet created",
        command_id: "cmd-task-101",
        receipt: "cmd-task-101",
        context_token: nil,
        data: Coordinator::Write::CommandReceiptData::ChangeSet.new(change_set_id: "CS-101"),
        warnings: [],
        next_actions: []
      )
    )
  end
end
