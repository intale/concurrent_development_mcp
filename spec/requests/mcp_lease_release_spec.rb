# frozen_string_literal: true

RSpec.describe "MCP work_intention_set_withdraw Task boundary", :event_store do
  RELEASE_PROTOCOL_VERSION = "2026-07-28"
  RELEASE_TASKS_EXTENSION = "io.modelcontextprotocol/tasks"
  RELEASE_CHANGE_SET_ID = "CS-MCP-RELEASE"
  RELEASE_WORK_ITEM_ID = "W-MCP-RELEASE"
  RELEASE_ATTEMPT_ID = "A-MCP-RELEASE"
  RELEASE_BASE_COMMIT_OID = "a" * 40

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:repository_id) { RepositoryScenario::DEFAULT_REPOSITORY_ID }
  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end

  it "durably withdraws the exact set, replays without duplicate facts, and preserves Saga trace identity" do
    seed_active_attempt
    reservation = Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 0)) { reserve_initial_set.value!.data }

    submitted_response, completed = Timecop.freeze(Time.utc(2026, 8, 22, 10, 5, 0)) do
      response = submit_release(
        command_id: "cmd-mcp-release",
        reservation:,
        request_id: 1
      )
      task_id = response.dig("result", "taskId")
      execute_task(task_id)
      [ response, task_request(task_id, request_id: 2) ]
    end
    task_id = submitted_response.dig("result", "taskId")
    result = completed.dig("result", "result")

    expect(task_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(completed.dig("result", "status")).to eq("completed")
    expect(result).to include(
      "isError" => false,
      "structuredContent" => include(
        "status" => "ok",
        "command_id" => "cmd-mcp-release",
        "data" => include(
          "change_set_id" => RELEASE_CHANGE_SET_ID,
          "work_item_id" => RELEASE_WORK_ITEM_ID,
          "attempt_id" => RELEASE_ATTEMPT_ID,
          "intention_set_id" => reservation.intention_set_id,
          "intention_count" => 2,
          "previous_expires_at" => "2026-08-22T10:10:00.000000Z",
          "withdrawn_at" => match(Coordinator::Shared::Types::TIMESTAMP_PATTERN)
        )
      )
    )

    submitted, started, task_completed = task_events(task_id)
    command_terminal = CommandTraceFixture.terminal(task_id, event_store:)
    target_events = work_intention_withdrawal_events(reservation) + [ command_terminal ]

    expect(started.causation_id).to eq(submitted.id)
    expect(target_events.map(&:causation_id).uniq).to eq([ started.id ])
    expect(task_completed.causation_id).to eq(command_terminal.id)
    expect(([ submitted, started, task_completed ] + target_events).map(&:correlation_id).uniq).to eq(
      [ submitted.correlation_id ]
    )
    expect(target_events).to all(satisfy do |event|
      !event.metadata.key?("correlation_id") && !event.metadata.key?("causation_id")
    end)

    replay_response = submit_release(
      command_id: "cmd-mcp-release",
      reservation:,
      request_id: 3
    )
    replay_task_id = replay_response.dig("result", "taskId")
    execute_task(replay_task_id)
    replayed = task_request(replay_task_id, request_id: 4)

    expect(replay_task_id).to eq(task_id)
    expect(replayed.dig("result", "result")).to eq(result)
    expect(work_intention_withdrawal_events(reservation).length).to eq(2)
    expect(CommandTraceFixture.events(task_id, event_store:).map(&:type)).to eq(
      [ "CommandRegistered", "CommandSucceeded" ]
    )
    expect(task_events(replay_task_id).map(&:correlation_id).uniq.length).to eq(1)
  end

  it "completes stale fencing evidence as a Task denial and rejects malformed input before Task allocation" do
    seed_active_attempt
    reservation = reserve_initial_set.value!.data
    stale_intentions = intention_inputs(reservation)
    stale_intentions.first[:fencing_token] += 1
    stale_response = submit_release(
      command_id: "cmd-mcp-release-stale",
      reservation:,
      intentions: stale_intentions,
      request_id: 1
    )
    task_id = stale_response.dig("result", "taskId")

    execute_task(task_id)
    stale = task_request(task_id, request_id: 2)

    expect(stale.dig("result", "status")).to eq("completed")
    expect(stale.dig("result", "result")).to include(
      "isError" => true,
      "structuredContent" => include(
        "status" => "conflict",
        "data" => include("code" => "work_intention_reference_mismatch")
      )
    )
    expect(CommandTraceFixture.events(task_id, event_store:).map(&:type)).to eq(
      [ "CommandRegistered", "CommandRejected" ]
    )
    expect(work_intention_withdrawal_events(reservation)).to be_empty

    malformed = submit_release(
      command_id: "cmd-mcp-release-malformed",
      reservation:,
      intention_set_id: "not-a-uuid",
      request_id: 3
    )

    expect(malformed.dig("result", "resultType")).to eq("complete")
    expect(malformed.dig("result", "isError")).to be(true)
    expect(malformed.dig("result", "content", 0, "text")).to include("intention_set_id")
    expect(task_events_for_command("cmd-mcp-release-malformed")).to be_empty
  end

  private

  def submit_release(
    command_id:,
    reservation:,
    request_id:,
    intentions: intention_inputs(reservation),
    intention_set_id: reservation.intention_set_id
  )
    mcp_request(
      id: request_id,
      method: "tools/call",
      name: "work_intention_set_withdraw",
      params: {
        name: "work_intention_set_withdraw",
        arguments: {
          command_id:,
          actor: { kind: "agent", id: "agent-a" },
          change_set_id: RELEASE_CHANGE_SET_ID,
          work_item_id: RELEASE_WORK_ITEM_ID,
          attempt_id: RELEASE_ATTEMPT_ID,
          intention_set_id:,
          intentions:
        }
      }
    )
  end

  def intention_inputs(reservation)
    reservation.intentions.map do |reference|
      {
        resource_id: reference.resource_id,
        intention_id: reference.intention_id,
        fencing_token: reference.fencing_token
      }
    end
  end

  def task_request(task_id, request_id:)
    mcp_request(
      id: request_id,
      method: "tasks/get",
      name: task_id,
      params: { taskId: task_id }
    )
  end

  def mcp_request(id:, method:, name:, params:)
    request_params = params.merge(
      _meta: {
        "io.modelcontextprotocol/protocolVersion": RELEASE_PROTOCOL_VERSION,
        "io.modelcontextprotocol/clientCapabilities": {
          extensions: { RELEASE_TASKS_EXTENSION => {} }
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
        "MCP-Protocol-Version" => RELEASE_PROTOCOL_VERSION,
        "Mcp-Method" => method,
        "Mcp-Name" => name
      }
    )
    expect(session.response.status).to eq(200), session.response.body
    JSON.parse(session.response.body)
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

  def reserve_initial_set
    resource_ids = %w[app/a.rb app/b.rb].map { resolve_resource(_1) }
    Coordinator::Write::Operations::ExecuteReserveWriteSet.new(event_store:).call(
      command_id: "seed-reserve-#{RELEASE_ATTEMPT_ID}",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: RELEASE_CHANGE_SET_ID,
      work_item_id: RELEASE_WORK_ITEM_ID,
      attempt_id: RELEASE_ATTEMPT_ID,
      repository_id:,
      base_commit_oid: RELEASE_BASE_COMMIT_OID,
      resources: resource_ids.map { { resource_id: _1 } },
      ttl_seconds: 600
    )
  end

  def seed_active_attempt
    RepositoryScenario.register(event_store:)
    Coordinator::Write::Operations::ExecuteCreateChangeSet.new(event_store:).call(
      command_id: "seed-create-#{RELEASE_CHANGE_SET_ID}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: RELEASE_CHANGE_SET_ID,
      goal: "Coordinate MCP work-intention withdrawal",
      acceptance_criteria: [ "Every intention is withdrawn together" ]
    ).value!
    Coordinator::Write::Operations::ExecuteCreateWorkItem.new(event_store:).call(
      command_id: "seed-create-#{RELEASE_WORK_ITEM_ID}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: RELEASE_CHANGE_SET_ID,
      work_item_id: RELEASE_WORK_ITEM_ID,
      repository_id:,
      goal: "Implement the coordinated change",
      acceptance_criteria: [ "Release retains every fencing identity" ]
    ).value!
    Coordinator::Write::Operations::ExecuteActivateChangeSet.new(event_store:).call(
      command_id: "seed-activate-#{RELEASE_CHANGE_SET_ID}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: RELEASE_CHANGE_SET_ID
    ).value!
    activation = event_store.read(
      streams.change_set(RELEASE_CHANGE_SET_ID),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACQUISITION
    ).find { _1.type == "ChangeSetActivated" }
    Coordinator::Processes::ProcessManagers::ChangeSetReadiness.new(event_store:).call(activation)
    Coordinator::Write::Operations::ExecuteAcquireWorkItem.new(event_store:).call(
      command_id: "seed-acquire-#{RELEASE_ATTEMPT_ID}",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: RELEASE_CHANGE_SET_ID,
      work_item_id: RELEASE_WORK_ITEM_ID,
      attempt_id: RELEASE_ATTEMPT_ID,
      base_snapshots: [ { repository_id:, commit_oid: RELEASE_BASE_COMMIT_OID } ]
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
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_HISTORY)
  end

  def work_intention_withdrawal_events(reservation)
    reservation.intentions.flat_map do |reference|
      event_store.read_grouped(
        streams.resource_work_intention(reference.intention_id),
        Coordinator::Write::EventQueries::WORK_INTENTION_STATE
      ).select { _1.type == "ResourceWorkIntentionWithdrawn" }
    end
  end

  def resolve_resource(path)
    @resource_ids ||= {}
    @resource_ids[path] ||= ResourceScenario.resolve(event_store:, repository_id:, kind: "file", path:)
  end
end
