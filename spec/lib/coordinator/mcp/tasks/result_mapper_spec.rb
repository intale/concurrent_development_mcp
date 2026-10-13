# frozen_string_literal: true

RSpec.describe Coordinator::Mcp::Tasks::ResultMapper do
  subject(:mapper) { described_class.new }

  let(:task_id) { "01919191-9191-7191-8191-919191919191" }
  let(:submitted_at) { "2026-08-22T10:00:00.000000Z" }
  let(:submitted) do
    Coordinator::Write::Events::CoordinationTaskSubmittedV3.new(
      task_id:,
      tool_name: "change_set_create",
      command_id: target_command.command_id,
      command_input: Coordinator::Write::CommandInputDigest.new.document(target_command),
      ttl_ms: nil,
      poll_interval_ms: 500
    )
  end
  let(:started) do
    Coordinator::Write::Events::CoordinationTaskExecutionStartedV2.new(task_id:)
  end
  let(:target_command) do
    Coordinator::Write::Commands::CreateChangeSet.new(
      command_id: "01919191-9191-7192-8191-919191919191",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "agent-a"),
      change_set_id: "CS-task-wire",
      goal: "Serialize every Task state",
      acceptance_criteria: [ "The wire shape stays strict" ]
    )
  end

  it "serializes a newly durable Task as a flat CreateTaskResult" do
    result = mapper.created(state(submitted)).to_h

    expect(result).to eq(
      taskId: task_id,
      createdAt: submitted_at,
      lastUpdatedAt: submitted_at,
      ttlMs: nil,
      pollIntervalMs: 500,
      resultType: "task",
      status: "working",
      statusMessage: mapper.detailed(state(submitted)).statusMessage
    )
  end

  it "includes the cooperative cancellation message while execution remains working" do
    cancellation = Coordinator::Write::Events::CoordinationTaskCancellationRequestedV2.new(
      task_id:,
      reason: nil
    )

    result = mapper.detailed(state(submitted, started, cancellation)).to_h

    expect(result).to include(
      resultType: "complete",
      status: "working",
      statusMessage: a_string_including("Cancellation requested; execution may still complete", "request is durably recorded")
    )
  end

  it "presents a semantic completion as the exact CallToolResult" do
    completed = Coordinator::Write::Events::CoordinationTaskCompletedV3.new(task_id:)

    result = mapper.detailed(
      state(submitted, started, completed),
      semantic_result: semantic_success
    ).to_h

    expect(result).to include(resultType: "complete", status: "completed")
    expect(result.fetch(:result)).to eq(
      Coordinator::Mcp::Tasks::SemanticResultPresenterV1.new.call(semantic_success).to_h
    )
  end

  it "never disguises an authoritative terminal state as projection-pending work" do
    completed = Coordinator::Write::Events::CoordinationTaskCompletedV3.new(task_id:)

    expect { mapper.detailed(state(submitted, started, completed)) }.to raise_error(KeyError, /authoritative result/)
  end

  it "preserves the actual terminal status when replay returns the original Task handle" do
    completed = Coordinator::Write::Events::CoordinationTaskCompletedV3.new(task_id:)
    result = mapper.created(state(submitted, started, completed)).to_h
    expect(result).to include(status: "completed", statusMessage: a_string_including("original Task is completed", "tasks/get"))
  end

  it "keeps JSON-RPC failure and cancellation as distinct terminal wire variants" do
    failed = Coordinator::Write::Events::CoordinationTaskFailedV2.new(
      task_id:,
      code: "internal_error",
      reason: "Internal error",
      retryable: false
    )
    cancelled = Coordinator::Write::Events::CoordinationTaskCancelledV2.new(
      task_id:,
      reason: "Cancelled before execution"
    )

    failed_result = mapper.detailed(state(submitted, started, failed)).to_h
    cancelled_result = mapper.detailed(state(submitted, cancelled)).to_h

    expect(failed_result).to include(
      status: "failed",
      statusMessage: a_string_including("Internal error", "does not establish whether target effects committed"),
      error: { code: -32_603, message: "Internal error" }
    )
    expect(cancelled_result).to include(
      status: "cancelled",
      statusMessage: a_string_including("Cancelled before execution", "does not roll back")
    )
    expect(cancelled_result).not_to have_key(:error)
    expect(cancelled_result).not_to have_key(:result)
  end

  def state(*events)
    Coordinator::Write::Domain::CoordinationTasks::State.reduce(
      events,
      occurred_at: events.each_index.map { |index| "2026-08-22T10:00:0#{index}.000000Z" }
    )
  end

  def semantic_success
    @semantic_success ||= Coordinator::Write::Tasks::SemanticResultV1::Success.new(
      kind: "success",
      summary: "Target command completed",
      command_id: target_command.command_id,
      receipt: target_command.command_id,
      data: Coordinator::Write::CommandReceiptData::ChangeSet.new(
        change_set_id: "CS-task-wire"
      ),
      warnings: [],
      next_actions: [],
      completion: Coordinator::Write::Tasks::CompletionGuaranteeV1.new(scope: "command", outcome: "succeeded",
        effects: "committed", read_back_required: false, read_models: "eventually_consistent")
    )
  end
end
