# frozen_string_literal: true

RSpec.describe "MCP history migration start", :event_store do
  PROTOCOL_VERSION = "2026-07-28"
  TASKS_EXTENSION = "io.modelcontextprotocol/tasks"

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap { _1.host! "localhost" }
  end

  it "freezes the source before Task facts and replays by caller input rather than derived values" do
    repository_id = SecureRandom.uuid_v7
    payload = Coordinator::Write::Events::RepositoryRegisteredV2.new(
      repository_id:, scope: "project:migration-start", repository_key: "probe"
    )
    anchor = event_store.append(
      streams.repository(repository_id),
      [ PgEventstore::Event.new(type: "RepositoryRegistered", data: payload.to_h, metadata: { "schema_version" => 2 }) ]
    ).sole
    arguments = {
      command_id: "migration-public-start-1",
      actor: { kind: "agent", id: "migration-agent" },
      page_size: 250
    }

    collector = ReportedErrorCollector.new
    Rails.error.subscribe(collector)
    submission = call_tool(arguments)
    replay = call_tool(arguments)
    raise collector.errors.first if collector.errors.any?
    expect(submission["error"]).to be_nil, submission.inspect
    task_id = submission.dig("result", "taskId")
    submitted = task_events(task_id).find { _1.type == "CoordinationTaskSubmitted" }

    expect(replay.fetch("result")).to eq(submission.fetch("result"))
    Coordinator::Container["process_managers.coordination_task_executor"].call(submitted)
    CommandResultFixture.project(task_id, event_store:)
    result = task_request(task_id).dig("result", "result")
    data = result.dig("structuredContent", "data")
    history = event_store.read(
      streams.history_migration(data.fetch("migration_id")),
      Coordinator::Write::EventReadCriteria.new(
        event_types: Coordinator::Write::Operations::ExecuteStartHistoryMigration::EVENT_TYPES,
        maximum_count: 6,
        direction: :asc
      )
    )

    expect(result).to include("isError" => false)
    expect(data).to include(
      "source_config_name" => "default",
      "target_config_name" => "migration_target",
      "source_upper_position" => anchor.global_position,
      "page_size" => 250,
      "outcome" => "started"
    )
    expect(history.map(&:type)).to eq(Coordinator::Write::Operations::ExecuteStartHistoryMigration::EVENT_TYPES)
    expect(history.first.global_position).to be > anchor.global_position
  ensure
    Rails.error.unsubscribe(collector) if collector
  end

  private

  def call_tool(arguments)
    mcp_request(
      method: "tools/call",
      name: "history_migration_start",
      params: { name: "history_migration_start", arguments: }
    )
  end

  def task_request(task_id)
    mcp_request(method: "tasks/get", name: task_id, params: { taskId: task_id })
  end

  def mcp_request(method:, name:, params:)
    session.post(
      "/mcp",
      params: JSON.generate(
        jsonrpc: "2.0",
        id: SecureRandom.random_number(1_000_000),
        method:,
        params: params.merge(
          _meta: {
            "io.modelcontextprotocol/protocolVersion" => PROTOCOL_VERSION,
            "io.modelcontextprotocol/clientCapabilities" => { extensions: { TASKS_EXTENSION => {} } },
            "io.modelcontextprotocol/clientInfo" => { name: "rspec", version: "1.0" }
          }
        )
      ),
      headers: {
        "Content-Type" => "application/json",
        "Accept" => "application/json, text/event-stream",
        "MCP-Protocol-Version" => PROTOCOL_VERSION,
        "Mcp-Method" => method,
        "Mcp-Name" => name
      }
    )
    expect(session.response.status).to eq(200), session.response.body
    JSON.parse(session.response.body)
  end

  def task_events(task_id)
    event_store.read(streams.coordination_task(task_id), Coordinator::Write::EventQueries::COORDINATION_TASK_HISTORY)
  end
end
