# frozen_string_literal: true

module OperationBatchAcceptanceWorld
  def submit_skill_batch(items, pause_at: nil)
    @operation_batch_id ||= SecureRandom.uuid_v7
    @operation_batch_command_id = "cmd-cuc-batch-#{@operation_batch_id}"
    install_contention_barrier(
      operation: pause_at,
      command_ids: [ @operation_batch_command_id ]
    ) if pause_at
    response = call_tool(
      "skill_publish_batch",
      {
        command_id: @operation_batch_command_id,
        actor: { kind: "agent", id: "import-agent" },
        batch_id: @operation_batch_id,
        items:
      },
      client_id: "import-agent"
    )
    @operation_batch_task_id = response.dig("result", "taskId")
    assert_acceptance(@operation_batch_task_id, "skill_publish_batch returned no Task: #{response.inspect}")
    start_process_subscriptions
    @operation_batch_task = await_task_terminal(
      @operation_batch_task_id,
      client_id: "import-agent"
    )
  end

  def batch_skill_item(index:, name:, expected_revision: 0)
    {
      command_id: "cmd-cuc-batch-item-#{@operation_batch_id || "pending"}-#{index}",
      actor: { kind: "agent", id: "import-agent" },
      name:,
      scope: "project:cucumber-batch",
      expected_revision:,
      description: "Imported Skill #{name}",
      instructions: "Apply imported Skill #{name}.",
      assets: []
    }
  end

  def operation_batch_events
    event_store.read(
      streams.operation_batch(@operation_batch_id),
      Coordinator::Write::EventQueries::OPERATION_BATCH_HISTORY
    )
  end

  def restart_operation_batch_after_page
    await_contention_evidence
    stopping = Thread.new { stop_process_subscriptions }
    release_contention_barrier
    stopping.value
    restart_process_subscriptions
    await_operation_batch_terminal
  end

  def project_operation_batch(events)
    expected = operation_batch_expectation(events)
    await_read_model("Operation Batch #{@operation_batch_id} to expose #{expected.fetch(:status)}") do
      view = operation_batch_view
      matched = view && expected.all? { |key, value| view[key.to_s] == value }
      [ matched, view ]
    end
  end

  def operation_batch_view
    call_tool(
      "operation_batch_get",
      { batch_id: @operation_batch_id, limit: 100 }
    ).dig("result", "structuredContent", "data", "batch")
  end

  def await_operation_batch_terminal
    eventually("Operation Batch #{@operation_batch_id} to become terminal") do
      events = operation_batch_events
      terminal = events.any? { %w[OperationBatchCompleted OperationBatchCancelled].include?(_1.type) }
      [ terminal, events.map(&:type) ]
    end
  end

  private

  def operation_batch_expectation(events)
    terminal = events.reverse.find do |event|
      %w[OperationBatchCompleted OperationBatchCancelled].include?(event.type)
    end
    return terminal_expectation(terminal) if terminal

    {
      status: "running",
      succeeded: events.count { _1.type == "OperationBatchItemSucceeded" },
      rejected: events.count { _1.type == "OperationBatchItemRejected" }
    }
  end

  def terminal_expectation(event)
    status =
      if event.type == "OperationBatchCancelled"
        "cancelled"
      elsif event.data.fetch("rejected").positive?
        "completed_with_errors"
      else
        "completed"
      end
    {
      status:,
      succeeded: event.data.fetch("succeeded"),
      rejected: event.data.fetch("rejected"),
      not_run: event.type == "OperationBatchCancelled" ? event.data.fetch("not_run") : 0
    }
  end
end

World(OperationBatchAcceptanceWorld)
