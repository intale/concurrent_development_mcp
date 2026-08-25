# frozen_string_literal: true

module OperationBatchAcceptanceWorld
  def submit_skill_batch(items)
    @operation_batch_id ||= SecureRandom.uuid_v7
    @operation_batch_task_id = submit_and_execute(
      "skill_publish_batch",
      command_id: "cmd-cuc-batch-#{@operation_batch_id}",
      actor: { kind: "agent", id: "import-agent" },
      batch_id: @operation_batch_id,
      items:
    )
    @operation_batch_task = task_request("tasks/get", @operation_batch_task_id)
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

  def run_operation_batch_sources(redeliver_creation: false)
    runner = Coordinator::Container["process_managers.operation_batch_runner"]
    creation = operation_batch_events.find { _1.type == "OperationBatchCreated" }
    runner.call(creation)
    runner.call(creation) if redeliver_creation

    loop do
      terminal = operation_batch_events.any? { %w[OperationBatchCompleted OperationBatchCancelled].include?(_1.type) }
      break if terminal

      continuation = operation_batch_events.reverse.find do |event|
        event.type == "OperationBatchContinuationRequested" && !@delivered_continuations.to_a.include?(event.id)
      end
      assert_acceptance(continuation, "Batch has pending items without a continuation fact")
      @delivered_continuations ||= []
      @delivered_continuations << continuation.id
      runner.call(continuation)
    end
  end

  def project_operation_batch(events)
    projector = Coordinator::Container["projectors.operation_batches_v1"]
    events.each { projector.call(_1) }
  end

  def operation_batch_view
    call_tool(
      "operation_batch_get",
      { batch_id: @operation_batch_id, limit: 100 }
    ).dig("result", "structuredContent", "data", "batch")
  end
end

World(OperationBatchAcceptanceWorld)
