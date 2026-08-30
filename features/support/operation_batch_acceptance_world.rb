# frozen_string_literal: true

module OperationBatchAcceptanceWorld
  def submit_skill_batch(items, pause_at: nil)
    @operation_batch_id ||= SecureRandom.uuid_v7
    @submitted_operation_batch_items = JSON.parse(JSON.generate(items))
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

  def operation_batch_events(batch_id: @operation_batch_id)
    event_store.read(
      streams.operation_batch(batch_id),
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

  def project_operation_batch(
    events,
    batch_id: @operation_batch_id,
    timeout_seconds: LiveSubscriptions::DEFAULT_TIMEOUT_SECONDS
  )
    expected = operation_batch_expectation(events)
    await_read_model(
      "Operation Batch #{batch_id} to expose #{expected.fetch(:status)}",
      timeout_seconds:
    ) do
      view = operation_batch_view(batch_id:, limit: 1)
      matched = view && expected.all? { |key, value| view[key.to_s] == value }
      [ matched, view ]
    end
  end

  def operation_batch_view(batch_id: @operation_batch_id, after_index: nil, limit: 100)
    call_tool(
      "operation_batch_get",
      { batch_id:, after_index:, limit: }
    ).dig("result", "structuredContent", "data", "batch")
  end

  def operation_batch_manifest(batch_id: @operation_batch_id, limit: 25)
    items = []
    after_index = nil
    pages = []

    loop do
      page = operation_batch_view(batch_id:, after_index:, limit:)
      pages << page
      items.concat(page.fetch("items"))
      break unless page.fetch("has_more")

      after_index = page.fetch("next_after_index")
    end

    { pages:, items: }
  end

  def resubmit_not_run_items
    @cancelled_operation_batch_id = @operation_batch_id
    manifest = operation_batch_manifest(batch_id: @cancelled_operation_batch_id)
    @completed_prefix_command_ids = manifest.fetch(:items)
      .select { _1.fetch("status") == "succeeded" }
      .map { _1.fetch("command_id") }
    not_run = manifest.fetch(:items).select { _1.fetch("status") == "not_run" }
    assert_acceptance_equal(1, not_run.length, "Not-run manifest selection")

    @operation_batch_id = SecureRandom.uuid_v7
    @resumed_operation_batch_id = @operation_batch_id
    submit_skill_batch(not_run.map { _1.fetch("arguments") })
    await_operation_batch_terminal
    project_operation_batch(operation_batch_events)
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
