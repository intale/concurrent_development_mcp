# frozen_string_literal: true

RSpec.describe "ART-01 MCP Development Artifacts", :event_store, :read_model do
  ART_PROTOCOL_VERSION = "2026-07-28"
  ART_TASKS_EXTENSION = "io.modelcontextprotocol/tasks"

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end

  it "captures through a Task and independently serves metadata and passive content" do
    task_id = call_tool("development_artifact_capture", capture_input, id: 1)
      .dig("result", "taskId")
    execute_task(task_id)
    outcome = task_request("tasks/get", task_id, id: 2)
      .dig("result", "result", "structuredContent")
    artifact_id = outcome.dig("data", "artifact_id")

    expect(outcome).to include(
      "status" => "ok",
      "data" => include(
        "outcome" => "captured",
        "artifact_id" => a_string_matching(Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_ID_PATTERN)
      )
    )
    artifact_events(artifact_id).each do |event|
      Coordinator::Container["projectors.development_artifacts_v1"].call(event)
    end

    metadata = call_tool("development_artifact_get", { artifact_id: }, id: 3)
      .dig("result", "structuredContent")
    content = call_tool("development_artifact_content_get", { artifact_id: }, id: 4)
      .dig("result", "structuredContent")
    expect(metadata.dig("data", "artifact", "artifact")).to include(
      "artifact_id" => artifact_id,
      "scope" => "project:alpha"
    )
    expect(metadata.to_s).not_to include("MCP artifact body")
    expect(content.dig("data", "content")).to include(
      "text" => "MCP artifact body\n",
      "base64" => nil
    )
    expect(content.fetch("warnings").sole).to include("passive data")
  end

  it "runs capture and relation batches as idempotent Operation Batch Sagas" do
    batch_id = SecureRandom.uuid_v7
    created = call_tool(
      "development_artifact_capture_batch",
      {
        command_id: "cmd-artifact-capture-batch",
        actor: { kind: "agent", id: "agent-mcp-artifact" },
        batch_id:,
        items: [
          capture_input(command_id: "cmd-artifact-batch-1", locator: "one.md", text: "one\n"),
          capture_input(command_id: "cmd-artifact-batch-2", locator: "two.md", text: "two\n")
        ]
      },
      id: 1
    )
    execute_task(created.dig("result", "taskId"))
    run_batch(batch_id)
    artifact_ids = %w[cmd-artifact-batch-1 cmd-artifact-batch-2].map do |command_id|
      load_completion(command_id).data.artifact_id
    end

    relation_batch_id = SecureRandom.uuid_v7
    related = call_tool(
      "development_artifact_relation_declare_batch",
      {
        command_id: "cmd-artifact-relation-batch",
        actor: { kind: "agent", id: "agent-mcp-artifact" },
        batch_id: relation_batch_id,
        items: [
          {
            command_id: "cmd-artifact-batch-relation-1",
            actor: { kind: "agent", id: "agent-mcp-artifact" },
            source_artifact_id: artifact_ids.first,
            relation: "derived_from",
            target: { kind: "artifact", id: artifact_ids.last },
            attributes: {}
          }
        ]
      },
      id: 2
    )
    execute_task(related.dig("result", "taskId"))
    run_batch(relation_batch_id)

    expect(load_completion("cmd-artifact-batch-relation-1").data).to have_attributes(
      source_artifact_id: artifact_ids.first,
      outcome: "declared"
    )
    expect(artifact_events(artifact_ids.first).map(&:type)).to eq(
      [ "DevelopmentArtifactCaptured", "DevelopmentArtifactRelationDeclared" ]
    )
  end

  def capture_input(
    command_id: "cmd-mcp-artifact",
    locator: "docs/mcp.md",
    text: "MCP artifact body\n"
  )
    {
      command_id:,
      actor: { kind: "agent", id: "agent-mcp-artifact" },
      scope: "project:alpha",
      title: "MCP Artifact",
      kind: "documentation",
      labels: %w[docs mcp],
      content: { encoding: "utf-8", media_type: "text/markdown", text: },
      source: {
        kind: "local_file",
        locator:,
        revision: nil,
        observed_at: "2026-08-25T16:00:00.000000Z",
        collector: "mcp-spec/v1"
      }
    }
  end

  def call_tool(name, arguments, id:)
    mcp_request(id:, method: "tools/call", name:, params: { name:, arguments: })
  end

  def task_request(method, task_id, id:)
    mcp_request(id:, method:, name: task_id, params: { taskId: task_id })
  end

  def mcp_request(id:, method:, params:, name:)
    session.post(
      "/mcp",
      params: JSON.generate(jsonrpc: "2.0", id:, method:, params: modern_params(params)),
      headers: {
        "Content-Type" => "application/json",
        "Accept" => "application/json, text/event-stream",
        "MCP-Protocol-Version" => ART_PROTOCOL_VERSION,
        "Mcp-Method" => method,
        "Mcp-Name" => name
      }
    )
    expect(session.response.status).to be_between(200, 299), session.response.body
    JSON.parse(session.response.body)
  end

  def modern_params(params)
    params.merge(
      _meta: {
        "io.modelcontextprotocol/protocolVersion" => ART_PROTOCOL_VERSION,
        "io.modelcontextprotocol/clientCapabilities" => {
          extensions: { ART_TASKS_EXTENSION => {} }
        },
        "io.modelcontextprotocol/clientInfo" => { name: "rspec", version: "1.0" }
      }
    )
  end

  def execute_task(task_id)
    submitted = task_events(task_id).find { _1.type == "CoordinationTaskSubmitted" }
    Coordinator::Container["process_managers.coordination_task_executor"].call(submitted)
  end

  def run_batch(batch_id)
    created = batch_events(batch_id).find { _1.type == "OperationBatchCreated" }
    Coordinator::Container["process_managers.operation_batch_runner"].call(created)
  end

  def task_events(task_id)
    event_store.read(
      streams.coordination_task(task_id),
      Coordinator::Write::EventQueries::COORDINATION_TASK_HISTORY
    )
  end

  def batch_events(batch_id)
    event_store.read(
      streams.operation_batch(batch_id),
      Coordinator::Write::EventQueries::OPERATION_BATCH_HISTORY
    )
  end

  def artifact_events(artifact_id)
    event_store.read(
      streams.development_artifact(artifact_id),
      Coordinator::Write::EventQueries::DEVELOPMENT_ARTIFACT_HISTORY
    )
  end

  def load_completion(command_id)
    event = event_store.read(
      streams.command(command_id),
      Coordinator::Write::EventQueries::COMMAND_COMPLETION
    ).sole
    Coordinator::Write::EventSchemaRegistry.new.load(
      type: event.type,
      schema_version: event.metadata.fetch("schema_version"),
      data: event.data
    )
  end
end
