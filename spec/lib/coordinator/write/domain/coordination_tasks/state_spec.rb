# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::CoordinationTasks::State do
  let(:task_id) { "01919191-9191-7191-8191-919191919191" }
  let(:submitted) { task_submitted(task_id:) }

  it "folds a completed Task from its bounded authoritative history" do
    started = Coordinator::Write::Events::CoordinationTaskExecutionStartedV2.new(task_id:)
    completed = Coordinator::Write::Events::CoordinationTaskCompletedV3.new(task_id:)

    state = described_class.reduce(
      [ submitted, started, completed ],
      occurred_at: timestamps(3)
    )

    expect(state.status).to eq("completed")
    expect(state.started).to be(true)
    expect(state.semantic_result).to be_nil
    expect(state.last_updated_at).to eq("2026-08-22T06:30:02.000000Z")
  end

  it "retains availability while cooperative cancellation is outstanding" do
    state = described_class.reduce(
      [
        submitted,
        Coordinator::Write::Events::CoordinationTaskExecutionStartedV2.new(task_id:),
        Coordinator::Write::Events::CoordinationTaskCancellationRequestedV2.new(
          task_id:,
          reason: nil
        )
      ],
      occurred_at: timestamps(3)
    )

    expect(state.status).to eq("working")
    expect(state.cancellation_requested).to be(true)
    expect(state.status_message).to match(/Cancellation requested/)
  end

  it "rejects a terminal outcome before execution starts" do
    completed = Coordinator::Write::Events::CoordinationTaskCompletedV3.new(task_id:)

    expect do
      described_class.reduce([ submitted, completed ], occurred_at: timestamps(2))
    end.to raise_error(Coordinator::Write::InvalidCoordinationTaskHistory)
  end

  def task_submitted(task_id:)
    command = Coordinator::Write::Commands::CreateChangeSet.new(
      command_id: "01919191-9191-7192-8191-919191919191",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "agent-a"),
      change_set_id: "CS-101",
      goal: "Coordinate billing changes",
      acceptance_criteria: [ "Every target command is durable" ]
    )
    digest = Coordinator::Write::CommandInputDigest.new

    Coordinator::Write::Events::CoordinationTaskSubmittedV3.new(
      task_id:,
      tool_name: "change_set_create",
      command_id: command.command_id,
      command_input: digest.document(command),
      ttl_ms: nil,
      poll_interval_ms: 500
    )
  end

  def timestamps(count)
    count.times.map { |index| "2026-08-22T06:30:0#{index}.000000Z" }
  end
end
