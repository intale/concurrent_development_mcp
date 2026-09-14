# frozen_string_literal: true

RSpec.describe "BAT-01 MCP Operation Batches" do
  BATCH_PROTOCOL_VERSION = "2026-07-28"
  BATCH_TASKS_EXTENSION = "io.modelcontextprotocol/tasks"

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end

  it "accepts a Task-backed typed batch and runs its Saga", :event_store do
    batch_id = SecureRandom.uuid_v7
    arguments = {
      command_id: "batch-command",
      actor: { kind: "agent", id: "agent-1" },
      batch_id:,
      items: [
        skill_input(command_id: "item-1", expected_revision: 0),
        skill_input(command_id: "item-2", expected_revision: 0)
      ]
    }

    created = call_tool("skill_publish_batch", arguments, id: 1)
    task_id = created.dig("result", "taskId")
    execute_task(task_id)
    completed_task = task_request("tasks/get", task_id, id: 2)
    receipt = completed_task.dig("result", "result", "structuredContent")
    expect(receipt).to include(
      "status" => "ok",
      "data" => include(
        "batch_id" => batch_id,
        "target_tool" => "skill_publish",
        "total" => 2,
        "status" => "accepted"
      )
    )

    creation_events = batch_events(batch_id)
    created_event = creation_events.find { _1.type == "OperationBatchCreated" }
    expect(created_event.metadata.fetch("schema_version")).to eq(2)
    expect(created_event.data.keys).to eq([ "batch_id" ])
    expect(creation_events.map(&:type)).to eq(%w[
      OperationBatchCreated
      OperationBatchTargetSelected
      OperationBatchItemEnqueued
      OperationBatchItemEnqueued
    ])
    items = Coordinator::Write::OperationBatches::Loader.new(event_store:).call(batch_id).state.items
    expect(items.map(&:request_id)).to eq(%w[item-1 item-2])
    expect(items.map(&:command_id)).to all(match(Coordinator::Write::Types::UUID_V7_PATTERN))
    items.each do |item|
      expect(command_events(item.command_id).map(&:type)).to eq([ "CommandRegistered" ])
    end

    Coordinator::Container["process_managers.operation_batch_runner"].call(created_event)
    persisted_batch_events = batch_events(batch_id)
    expect(persisted_batch_events.map(&:type)).to eq(%w[
      OperationBatchCreated
      OperationBatchTargetSelected
      OperationBatchItemEnqueued
      OperationBatchItemEnqueued
      OperationBatchItemSucceeded
      OperationBatchItemCompletionLinked
      OperationBatchItemRejected
      OperationBatchItemCompletionLinked
      OperationBatchCompleted
    ])
    expect(persisted_batch_events.map(&:correlation_id).uniq).to contain_exactly(created_event.correlation_id)

    succeeded = persisted_batch_events.find { _1.type == "OperationBatchItemSucceeded" }
    rejected = persisted_batch_events.find { _1.type == "OperationBatchItemRejected" }
    links = persisted_batch_events.select { _1.type == "OperationBatchItemCompletionLinked" }
    expect(succeeded.data.keys).to match_array(%w[batch_id command_id index])
    expect(rejected.data.keys).to match_array(%w[batch_id code command_id index reason retryable])
    expect(links.map { _1.data.keys }).to all(match_array(%w[batch_id command_id completion index]))
    expect(persisted_batch_events.last.data.keys).to eq([ "batch_id" ])
    expect(command_events(items.fetch(0).command_id).map(&:type)).to eq(
      %w[CommandRegistered CommandSucceeded]
    )
    expect(command_events(items.fetch(1).command_id).map(&:type)).to eq(
      %w[CommandRegistered CommandRejected]
    )
  end

  it "serves directly persisted stale-available batch progress", :read_model do
    batch = create(:coordinator_read_operation_batch)
    first = create(
      :coordinator_read_operation_batch_item,
      operation_batch: batch,
      item_index: 0,
      command_id: "item-1",
      canonical_input_digest: "sha256:#{'b' * 64}"
    )
    second = create(
      :coordinator_read_operation_batch_item,
      operation_batch: batch,
      item_index: 1,
      command_id: "item-2",
      canonical_input_digest: "sha256:#{'c' * 64}"
    )
    create(
      :coordinator_read_operation_batch_outcome,
      operation_batch: batch,
      item_index: 0,
      command_id: first.command_id,
      canonical_input_digest: first.canonical_input_digest
    )
    create(
      :coordinator_read_operation_batch_outcome,
      :rejected,
      operation_batch: batch,
      item_index: 1,
      command_id: second.command_id,
      canonical_input_digest: second.canonical_input_digest
    )

    available = call_tool("operation_batch_get", { batch_id: batch.batch_id, limit: 100 }, id: 3)
      .dig("result", "structuredContent")
    expect(available).to include(
      "status" => "ok",
      "data" => include(
        "batch" => include(
          "batch_id" => batch.batch_id,
          "status" => "completed_with_errors",
          "succeeded" => 1,
          "rejected" => 1,
          "not_run" => 0
        )
      )
    )
    expect(available.dig("data", "batch", "items").map { _1.fetch("status") }).to eq(
      %w[succeeded rejected]
    )
  end

  it "rejects malformed nested items before allocating a Task", :event_store do
    response = call_tool(
      "skill_publish_batch",
      {
        command_id: "invalid-batch-command",
        actor: { kind: "agent", id: "agent-1" },
        batch_id: SecureRandom.uuid_v7,
        items: [ skill_input(command_id: "item-1", name: " bad ") ]
      },
      id: 1,
      expected_status: 400
    )

    expect(response.dig("error", "data", "code")).to eq("invalid_input")
    expect(task_events_for_command("invalid-batch-command")).to be_empty
  end

  def skill_input(**overrides)
    {
      command_id: "item-1",
      actor: { kind: "agent", id: "agent-1" },
      name: "review",
      scope: "project:alpha",
      expected_revision: 0,
      description: "Review a change",
      instructions: "Inspect the complete diff.",
      assets: []
    }.merge(overrides)
  end

  def call_tool(name, arguments, id:, expected_status: 200)
    mcp_request(id:, method: "tools/call", name:, params: { name:, arguments: }, expected_status:)
  end

  def task_request(method, task_id, id:)
    mcp_request(id:, method:, name: task_id, params: { taskId: task_id }, expected_status: 200)
  end

  def mcp_request(id:, method:, params:, name:, expected_status:)
    session.post(
      "/mcp",
      params: JSON.generate(jsonrpc: "2.0", id:, method:, params: modern_params(params)),
      headers: {
        "Content-Type" => "application/json",
        "Accept" => "application/json, text/event-stream",
        "MCP-Protocol-Version" => BATCH_PROTOCOL_VERSION,
        "Mcp-Method" => method,
        "Mcp-Name" => name
      }
    )
    expect(session.response.status).to eq(expected_status), session.response.body
    JSON.parse(session.response.body)
  end

  def modern_params(params)
    params.merge(
      _meta: {
        "io.modelcontextprotocol/protocolVersion" => BATCH_PROTOCOL_VERSION,
        "io.modelcontextprotocol/clientCapabilities" => {
          extensions: { BATCH_TASKS_EXTENSION => {} }
        },
        "io.modelcontextprotocol/clientInfo" => { name: "rspec", version: "1.0" }
      }
    )
  end

  def execute_task(task_id)
    submitted = task_events(task_id).find { _1.type == "CoordinationTaskSubmitted" }
    collector = ReportedErrorCollector.new
    Rails.error.subscribe(collector)
    Coordinator::Container["process_managers.coordination_task_executor"].call(submitted)
    raise collector.errors.first if collector.errors.any?
    CommandResultFixture.project(task_id, event_store:)
  ensure
    Rails.error.unsubscribe(collector) if collector
  end

  def task_events(task_id)
    event_store.read(streams.coordination_task(task_id), Coordinator::Write::EventQueries::COORDINATION_TASK_HISTORY)
  end

  def task_events_for_command(command_id)
    PgEventstore.client.read(
      PgEventstore::Stream.all_stream,
      options: {
        direction: :asc,
        max_count: 1,
        filter: {
          event_types: [
            { type: "CoordinationTaskSubmitted", markers: [ "command:#{command_id}" ] }
          ]
        }
      }
    )
  end

  def batch_events(batch_id)
    event_store.read(streams.operation_batch(batch_id), Coordinator::Write::EventQueries::OPERATION_BATCH_HISTORY)
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_HISTORY)
  end

  def load_event(event)
    Coordinator::Write::EventSchemaRegistry.new.load(
      type: event.type,
      schema_version: event.metadata.fetch("schema_version"),
      data: event.data
    )
  end
end
