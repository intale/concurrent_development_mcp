# frozen_string_literal: true

RSpec.describe "MCP write_set_expand Task boundary", :event_store do
  EXPAND_PROTOCOL_VERSION = "2026-07-28"
  EXPAND_TASKS_EXTENSION = "io.modelcontextprotocol/tasks"
  EXPAND_CHANGE_SET_ID = "CS-MCP-EXPAND"
  EXPAND_WORK_ITEM_ID = "W-MCP-EXPAND"
  EXPAND_ATTEMPT_ID = "A-MCP-EXPAND"
  EXPAND_BASE_COMMIT_OID = "a" * 40
  MCP_EXPAND_REPOSITORY_ID = RepositoryScenario::DEFAULT_REPOSITORY_ID

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:normalizer) { Coordinator::Write::FileResourceNormalizer.new }
  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end

  it "durably expands the current set and exposes exact trace readers across the Saga" do
    seed_active_attempt
    reservation = reserve_initial_set.value!.data

    submitted_response = submit_expansion(
      command_id: "cmd-mcp-expand",
      lease_set_id: reservation.lease_set_id,
      paths: [ "app/a.rb", "app/b.rb" ],
      request_id: 1
    )
    task_id = submitted_response.dig("result", "taskId")

    expect(task_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(command_events("cmd-mcp-expand")).to be_empty

    execute_task(task_id)
    completed = task_request(task_id, request_id: 2)
    result = completed.dig("result", "result")

    expect(completed.dig("result", "status")).to eq("completed")
    expect(result).to include(
      "isError" => false,
      "structuredContent" => include(
        "status" => "ok",
        "command_id" => "cmd-mcp-expand",
        "data" => include(
          "change_set_id" => EXPAND_CHANGE_SET_ID,
          "work_item_id" => EXPAND_WORK_ITEM_ID,
          "attempt_id" => EXPAND_ATTEMPT_ID,
          "lease_set_id" => reservation.lease_set_id,
          "resource_count" => 2,
          "expires_at" => reservation.expires_at,
          "added_resources" => [ include("resource_path" => "app/b.rb") ]
        )
      )
    )

    submitted, started, task_completed = task_events(task_id)
    target_events = lease_events("app/b.rb") +
                    expansion_events +
                    command_events("cmd-mcp-expand")
    command_completion = command_events("cmd-mcp-expand").sole

    expect(started.causation_id).to eq(submitted.id)
    expect(target_events.map(&:causation_id).uniq).to eq([ started.id ])
    expect(task_completed.causation_id).to eq(command_completion.id)
    expect(([ submitted, started, task_completed ] + target_events).map(&:correlation_id).uniq).to eq(
      [ submitted.correlation_id ]
    )
    expect(target_events).to all(satisfy do |event|
      !event.metadata.key?("correlation_id") && !event.metadata.key?("causation_id")
    end)
  end

  it "completes an unchanged decision as a Task error and rejects malformed input before Task allocation" do
    seed_active_attempt
    reservation = reserve_initial_set.value!.data
    unchanged_response = submit_expansion(
      command_id: "cmd-mcp-unchanged",
      lease_set_id: reservation.lease_set_id,
      paths: [ "app/a.rb" ],
      request_id: 1
    )
    task_id = unchanged_response.dig("result", "taskId")

    execute_task(task_id)
    unchanged = task_request(task_id, request_id: 2)

    expect(unchanged.dig("result", "status")).to eq("completed")
    expect(unchanged.dig("result", "result")).to include(
      "isError" => true,
      "structuredContent" => include(
        "status" => "denied",
        "data" => include("code" => "write_set_unchanged")
      )
    )
    expect(command_events("cmd-mcp-unchanged")).to be_empty
    expect(expansion_events).to be_empty

    malformed = submit_expansion(
      command_id: "cmd-mcp-malformed",
      lease_set_id: "not-a-uuid",
      paths: [ "app/b.rb" ],
      request_id: 3
    )

    expect(malformed.dig("result", "resultType")).to eq("complete")
    expect(malformed.dig("result", "isError")).to be(true)
    expect(malformed.dig("result", "content", 0, "text")).to include("lease_set_id")
    expect(task_events_for_command("cmd-mcp-malformed")).to be_empty
  end

  private

  def submit_expansion(command_id:, lease_set_id:, paths:, request_id:, expected_status: 200)
    mcp_request(
      id: request_id,
      method: "tools/call",
      name: "write_set_expand",
      expected_status:,
      params: {
        name: "write_set_expand",
        arguments: {
          command_id:,
          actor: { kind: "agent", id: "agent-a" },
          change_set_id: EXPAND_CHANGE_SET_ID,
          work_item_id: EXPAND_WORK_ITEM_ID,
          attempt_id: EXPAND_ATTEMPT_ID,
          lease_set_id:,
          repository_id: MCP_EXPAND_REPOSITORY_ID,
          base_commit_oid: EXPAND_BASE_COMMIT_OID,
          resources: paths.map { { kind: "file", path: _1 } }
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
        "io.modelcontextprotocol/protocolVersion": EXPAND_PROTOCOL_VERSION,
        "io.modelcontextprotocol/clientCapabilities": {
          extensions: { EXPAND_TASKS_EXTENSION => {} }
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
        "MCP-Protocol-Version" => EXPAND_PROTOCOL_VERSION,
        "Mcp-Method" => method,
        "Mcp-Name" => name
      }
    )
    expect(session.response.status).to eq(expected_status), session.response.body
    JSON.parse(session.response.body)
  end

  def execute_task(task_id)
    submitted = task_events(task_id).find { _1.type == "CoordinationTaskSubmitted" }
    collector = ReportedErrorCollector.new
    Rails.error.subscribe(collector)
    Coordinator::Container["process_managers.coordination_task_executor"].call(submitted)
    raise collector.errors.first if collector.errors.any?
  ensure
    Rails.error.unsubscribe(collector) if collector
  end

  def reserve_initial_set
    Coordinator::Write::Operations::ExecuteReserveWriteSet.new(event_store:).call(
      command_id: "seed-reserve-#{EXPAND_ATTEMPT_ID}",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: EXPAND_CHANGE_SET_ID,
      work_item_id: EXPAND_WORK_ITEM_ID,
      attempt_id: EXPAND_ATTEMPT_ID,
      repository_id: MCP_EXPAND_REPOSITORY_ID,
      base_commit_oid: EXPAND_BASE_COMMIT_OID,
      resources: [ { kind: "file", path: "app/a.rb" } ],
      lease_duration_seconds: 300
    )
  end

  def seed_active_attempt
    RepositoryScenario.register(event_store:)
    Coordinator::Write::Operations::ExecuteCreateChangeSet.new(event_store:).call(
      command_id: "seed-create-#{EXPAND_CHANGE_SET_ID}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: EXPAND_CHANGE_SET_ID,
      goal: "Coordinate MCP write-set expansion",
      acceptance_criteria: [ "Additional files require the same lease set" ]
    ).value!
    Coordinator::Write::Operations::ExecuteCreateWorkItem.new(event_store:).call(
      command_id: "seed-create-#{EXPAND_WORK_ITEM_ID}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: EXPAND_CHANGE_SET_ID,
      work_item_id: EXPAND_WORK_ITEM_ID,
      repository_id: MCP_EXPAND_REPOSITORY_ID,
      goal: "Implement the coordinated change",
      acceptance_criteria: [ "The expanded set remains atomic" ]
    ).value!
    Coordinator::Write::Operations::ExecuteActivateChangeSet.new(event_store:).call(
      command_id: "seed-activate-#{EXPAND_CHANGE_SET_ID}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: EXPAND_CHANGE_SET_ID
    ).value!
    activation = event_store.read(
      streams.change_set(EXPAND_CHANGE_SET_ID),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACQUISITION
    ).find { _1.type == "ChangeSetActivated" }
    Coordinator::Processes::ProcessManagers::ChangeSetReadiness.new(event_store:).call(activation)
    Coordinator::Write::Operations::ExecuteAcquireWorkItem.new(event_store:).call(
      command_id: "seed-acquire-#{EXPAND_ATTEMPT_ID}",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: EXPAND_CHANGE_SET_ID,
      work_item_id: EXPAND_WORK_ITEM_ID,
      attempt_id: EXPAND_ATTEMPT_ID,
      base_snapshots: [ { repository_id: MCP_EXPAND_REPOSITORY_ID, commit_oid: EXPAND_BASE_COMMIT_OID } ]
    ).value!
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
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_COMPLETION)
  end

  def expansion_events
    event_store.read(
      streams.attempt(EXPAND_ATTEMPT_ID),
      Coordinator::Write::EventQueries::ATTEMPT_FOR_WRITE_SET_EXPANSION
    ).select { _1.type == "WriteSetExpanded" }
  end

  def lease_events(path)
    resource = normalizer.call(
      repository_id: MCP_EXPAND_REPOSITORY_ID,
      scope: RepositoryScenario::DEFAULT_SCOPE,
      kind: "file",
      path:,
      base_blob_oid: nil
    ).value!
    event_store.read(
      streams.resource_lease(resource.resource_key_hash),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "ResourceLeaseAcquired" ],
        maximum_count: 10,
        direction: :asc
      )
    )
  end
end
