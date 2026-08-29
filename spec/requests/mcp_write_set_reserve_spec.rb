# frozen_string_literal: true

RSpec.describe "MCP write_set_reserve Task boundary", :event_store do
  WRITE_SET_PROTOCOL_VERSION = "2026-07-28"
  WRITE_SET_TASKS_EXTENSION = "io.modelcontextprotocol/tasks"
  CHANGE_SET_ID = "CS-MCP-LSE"
  BASE_COMMIT_OID = "a" * 40
  MCP_RESERVE_REPOSITORY_ID = RepositoryScenario::DEFAULT_REPOSITORY_ID

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end

  it "durably completes a reservation and a competing busy decision through Tasks" do
    seed_active_attempts(
      [
        [ "W-MCP-LSE-A", "A-MCP-LSE-A", "agent-a" ],
        [ "W-MCP-LSE-B", "A-MCP-LSE-B", "agent-b" ]
      ]
    )
    invoice_resource_id = resolve_resource("app/models/invoice.rb")
    schema_resource_id = resolve_resource("db/schema.rb")

    winner = submit_reservation(
      command_id: "cmd-mcp-lse-a",
      agent_id: "agent-a",
      work_item_id: "W-MCP-LSE-A",
      attempt_id: "A-MCP-LSE-A",
      resource_ids: [ invoice_resource_id, schema_resource_id ],
      request_id: 1
    )
    expect(winner).to include(
      "result" => include("resultType" => "task")
    ), winner.inspect
    winner_task_id = winner.dig("result", "taskId")
    expect(winner_task_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(command_events("cmd-mcp-lse-a")).to be_empty

    execute_task(winner_task_id)
    completed = task_request(winner_task_id, request_id: 2)
    result = completed.dig("result", "result")

    expect(completed.dig("result", "status")).to eq("completed")
    expect(result).to include(
      "isError" => false,
      "structuredContent" => include(
        "status" => "ok",
        "command_id" => "cmd-mcp-lse-a",
        "data" => include(
          "change_set_id" => CHANGE_SET_ID,
          "work_item_id" => "W-MCP-LSE-A",
          "attempt_id" => "A-MCP-LSE-A",
          "repository_id" => MCP_RESERVE_REPOSITORY_ID,
          "policy_version" => "coordinator-resource-lease/v2",
          "resources" => contain_exactly(
            include("resource_id" => invoice_resource_id),
            include("resource_id" => schema_resource_id)
          )
        )
      )
    )

    submitted, started, task_completed = task_events(winner_task_id)
    target_events = lease_events(invoice_resource_id) +
                    lease_events(schema_resource_id) +
                    write_set_events("A-MCP-LSE-A") +
                    command_events("cmd-mcp-lse-a")
    command_completion = command_events("cmd-mcp-lse-a").sole
    expect(started.causation_id).to eq(submitted.id)
    expect(target_events.map(&:causation_id).uniq).to eq([ started.id ])
    expect(task_completed.causation_id).to eq(command_completion.id)
    expect(([ submitted, started, task_completed ] + target_events).map(&:correlation_id).uniq).to eq(
      [ submitted.correlation_id ]
    )

    free_resource_id = resolve_resource("free.rb")
    contender = submit_reservation(
      command_id: "cmd-mcp-lse-b",
      agent_id: "agent-b",
      work_item_id: "W-MCP-LSE-B",
      attempt_id: "A-MCP-LSE-B",
      resource_ids: [ free_resource_id, schema_resource_id ],
      request_id: 3
    )
    contender_task_id = contender.dig("result", "taskId")
    execute_task(contender_task_id)
    denied = task_request(contender_task_id, request_id: 4)

    expect(denied.dig("result", "status")).to eq("completed")
    expect(denied.dig("result", "result")).to include(
      "isError" => true,
      "structuredContent" => include(
        "status" => "busy",
        "data" => include(
          "code" => "lease_busy",
          "details" => include(
            "owner_attempt_id" => "A-MCP-LSE-A",
            "owner_agent_id" => "agent-a",
            "fencing_token" => 1
          )
        )
      )
    )
    expect(lease_events(free_resource_id)).to be_empty
    expect(write_set_events("A-MCP-LSE-B")).to be_empty
    expect(command_events("cmd-mcp-lse-b")).to be_empty
  end

  it "rejects an invalid resource before allocating a Task" do
    response = submit_reservation(
      command_id: "cmd-mcp-lse-invalid",
      agent_id: "agent-a",
      work_item_id: "W-MCP-LSE-A",
      attempt_id: "A-MCP-LSE-A",
      resource_ids: [ "not-a-uuid" ],
      request_id: 1
    )

    expect(response.dig("result", "resultType")).to eq("complete")
    expect(response.dig("result", "isError")).to be(true)
    expect(response.dig("result", "content", 0, "text")).to include("resource_id")
    expect(task_events_for_command("cmd-mcp-lse-invalid")).to be_empty
  end

  def submit_reservation(
    command_id:,
    agent_id:,
    work_item_id:,
    attempt_id:,
    resource_ids:,
    request_id:,
    expected_status: 200
  )
    mcp_request(
      id: request_id,
      method: "tools/call",
      name: "write_set_reserve",
      expected_status:,
      params: {
        name: "write_set_reserve",
        arguments: {
          command_id:,
          actor: { kind: "agent", id: agent_id },
          change_set_id: CHANGE_SET_ID,
          work_item_id:,
          attempt_id:,
          repository_id: MCP_RESERVE_REPOSITORY_ID,
          base_commit_oid: BASE_COMMIT_OID,
          resources: resource_ids.map { { resource_id: _1 } },
          lease_duration_seconds: 300
        }
      }
    )
  end

  def task_request(task_id, request_id:)
    mcp_request(
      id: request_id,
      method: "tasks/get",
      name: task_id,
      params: { taskId: task_id }
    )
  end

  def mcp_request(id:, method:, name:, params:, expected_status: 200)
    request_params = params.merge(
      _meta: {
        "io.modelcontextprotocol/protocolVersion": WRITE_SET_PROTOCOL_VERSION,
        "io.modelcontextprotocol/clientCapabilities": {
          extensions: { WRITE_SET_TASKS_EXTENSION => {} }
        },
        "io.modelcontextprotocol/clientInfo": { name: "rspec", version: "1.0" }
      }
    )
    session.post(
      "/mcp",
      params: JSON.generate(jsonrpc: "2.0", id:, method:, params: request_params),
      headers: {
        "Content-Type" => "application/json",
        "Accept" => "application/json, text/event-stream",
        "MCP-Protocol-Version" => WRITE_SET_PROTOCOL_VERSION,
        "Mcp-Method" => method,
        "Mcp-Name" => name
      }
    )
    expect(session.response.status).to eq(expected_status), session.response.body
    JSON.parse(session.response.body)
  end

  def execute_task(task_id)
    submitted = task_events(task_id).find { _1.type == "CoordinationTaskSubmitted" }
    Coordinator::Container["process_managers.coordination_task_executor"].call(submitted)
  end

  def seed_active_attempts(attempts)
    RepositoryScenario.register(event_store:)
    Coordinator::Write::Operations::ExecuteCreateChangeSet.new(event_store:).call(
      command_id: "seed-create-#{CHANGE_SET_ID}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: CHANGE_SET_ID,
      goal: "Coordinate MCP resource leases",
      acceptance_criteria: [ "Overlapping agents cannot both write" ]
    ).value!
    attempts.each do |work_item_id, _attempt_id, _agent_id|
      Coordinator::Write::Operations::ExecuteCreateWorkItem.new(event_store:).call(
        command_id: "seed-create-#{work_item_id}",
        actor: { kind: "agent", id: "planner-1" },
        change_set_id: CHANGE_SET_ID,
        work_item_id:,
        repository_id: MCP_RESERVE_REPOSITORY_ID,
        goal: "Implement #{work_item_id}",
        acceptance_criteria: [ "The work is verifiable" ]
      ).value!
    end
    Coordinator::Write::Operations::ExecuteActivateChangeSet.new(event_store:).call(
      command_id: "seed-activate-#{CHANGE_SET_ID}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: CHANGE_SET_ID
    ).value!
    activation = event_store.read(
      streams.change_set(CHANGE_SET_ID),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACQUISITION
    ).find { _1.type == "ChangeSetActivated" }
    Coordinator::Processes::ProcessManagers::ChangeSetReadiness.new(event_store:).call(activation)
    attempts.each do |work_item_id, attempt_id, agent_id|
      Coordinator::Write::Operations::ExecuteAcquireWorkItem.new(event_store:).call(
        command_id: "seed-acquire-#{attempt_id}",
        actor: { kind: "agent", id: agent_id },
        change_set_id: CHANGE_SET_ID,
        work_item_id:,
        attempt_id:,
        base_snapshots: [ { repository_id: MCP_RESERVE_REPOSITORY_ID, commit_oid: BASE_COMMIT_OID } ]
      ).value!
    end
  end

  def task_events(task_id)
    event_store.read(
      streams.coordination_task(task_id),
      Coordinator::Write::EventQueries::COORDINATION_TASK_HISTORY
    )
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

  def command_events(command_id)
    event_store.read(
      streams.command(command_id),
      Coordinator::Write::EventQueries::COMMAND_COMPLETION
    )
  end

  def write_set_events(attempt_id)
    event_store.read(
      streams.attempt(attempt_id),
      Coordinator::Write::EventQueries::ATTEMPT_FOR_WRITE_SET_RESERVATION
    ).select { _1.type == "WriteSetReserved" }
  end

  def resolve_resource(path)
    @resource_ids ||= {}
    @resource_ids[path] ||= ResourceScenario.resolve(
      event_store:,
      repository_id: MCP_RESERVE_REPOSITORY_ID,
      kind: "file",
      path:
    )
  end

  def lease_events(resource_id)
    event_store.read(
      streams.resource_lease(resource_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "ResourceLeaseAcquired" ],
        maximum_count: 10,
        direction: :asc
      )
    )
  end
end
