# frozen_string_literal: true

RSpec.describe "MCP lease_renew Task boundary", :event_store do
  RENEW_PROTOCOL_VERSION = "2026-07-28"
  RENEW_TASKS_EXTENSION = "io.modelcontextprotocol/tasks"
  RENEW_CHANGE_SET_ID = "CS-MCP-RENEW"
  RENEW_WORK_ITEM_ID = "W-MCP-RENEW"
  RENEW_ATTEMPT_ID = "A-MCP-RENEW"
  RENEW_BASE_COMMIT_OID = "a" * 40

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:normalizer) { Coordinator::Write::FileResourceNormalizer.new }
  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end

  it "durably renews the exact set and exposes trace identity through persisted event readers" do
    seed_active_attempt
    reservation = Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 0)) { reserve_initial_set.value!.data }

    submitted_response, completed = Timecop.freeze(Time.utc(2026, 8, 22, 10, 5, 0)) do
      response = submit_renewal(
        command_id: "cmd-mcp-renew",
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
        "command_id" => "cmd-mcp-renew",
        "data" => include(
          "change_set_id" => RENEW_CHANGE_SET_ID,
          "work_item_id" => RENEW_WORK_ITEM_ID,
          "attempt_id" => RENEW_ATTEMPT_ID,
          "lease_set_id" => reservation.lease_set_id,
          "resource_count" => 2,
          "previous_expires_at" => "2026-08-22T10:10:00.000000Z",
          "expires_at" => "2026-08-22T10:20:00.000000Z"
        )
      )
    )

    submitted, started, task_completed = task_events(task_id)
    target_events = resource_renewal_events + write_set_renewal_events + command_events("cmd-mcp-renew")
    command_completion = command_events("cmd-mcp-renew").sole

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

  it "completes stale fencing evidence as a Task denial and rejects malformed input before Task allocation" do
    seed_active_attempt
    reservation = reserve_initial_set.value!.data
    stale_leases = lease_inputs(reservation)
    stale_leases.first[:fencing_token] += 1
    stale_response = submit_renewal(
      command_id: "cmd-mcp-renew-stale",
      reservation:,
      leases: stale_leases,
      request_id: 1
    )
    task_id = stale_response.dig("result", "taskId")

    execute_task(task_id)
    stale = task_request(task_id, request_id: 2)

    expect(stale.dig("result", "status")).to eq("completed")
    expect(stale.dig("result", "result")).to include(
      "isError" => true,
      "structuredContent" => include(
        "status" => "denied",
        "data" => include("code" => "lease_reference_mismatch")
      )
    )
    expect(command_events("cmd-mcp-renew-stale")).to be_empty
    expect(resource_renewal_events).to be_empty
    expect(write_set_renewal_events).to be_empty

    malformed = submit_renewal(
      command_id: "cmd-mcp-renew-malformed",
      reservation:,
      lease_set_id: "not-a-uuid",
      request_id: 3
    )

    expect(malformed.dig("result", "resultType")).to eq("complete")
    expect(malformed.dig("result", "isError")).to be(true)
    expect(malformed.dig("result", "content", 0, "text")).to include("lease_set_id")
    expect(task_events_for_command("cmd-mcp-renew-malformed")).to be_empty
  end

  private

  def submit_renewal(command_id:, reservation:, request_id:, leases: lease_inputs(reservation), lease_set_id: reservation.lease_set_id)
    mcp_request(
      id: request_id,
      method: "tools/call",
      name: "lease_renew",
      params: {
        name: "lease_renew",
        arguments: {
          command_id:,
          actor: { kind: "agent", id: "agent-a" },
          change_set_id: RENEW_CHANGE_SET_ID,
          work_item_id: RENEW_WORK_ITEM_ID,
          attempt_id: RENEW_ATTEMPT_ID,
          lease_set_id:,
          leases:,
          lease_duration_seconds: 900
        }
      }
    )
  end

  def lease_inputs(reservation)
    reservation.resources.map do |reference|
      {
        resource_key_hash: reference.resource_key_hash,
        lease_id: reference.lease_id,
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
        "io.modelcontextprotocol/protocolVersion": RENEW_PROTOCOL_VERSION,
        "io.modelcontextprotocol/clientCapabilities": {
          extensions: { RENEW_TASKS_EXTENSION => {} }
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
        "MCP-Protocol-Version" => RENEW_PROTOCOL_VERSION,
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
  ensure
    Rails.error.unsubscribe(collector) if collector
  end

  def reserve_initial_set
    Coordinator::Write::Operations::ExecuteReserveWriteSet.new(event_store:).call(
      command_id: "seed-reserve-#{RENEW_ATTEMPT_ID}",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: RENEW_CHANGE_SET_ID,
      work_item_id: RENEW_WORK_ITEM_ID,
      attempt_id: RENEW_ATTEMPT_ID,
      repository_id: "billing",
      base_commit_oid: RENEW_BASE_COMMIT_OID,
      resources: %w[app/a.rb app/b.rb].map { { kind: "file", path: _1 } },
      lease_duration_seconds: 600
    )
  end

  def seed_active_attempt
    Coordinator::Write::Operations::ExecuteCreateChangeSet.new(event_store:).call(
      command_id: "seed-create-#{RENEW_CHANGE_SET_ID}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: RENEW_CHANGE_SET_ID,
      goal: "Coordinate MCP lease renewal",
      acceptance_criteria: [ "Every lease remains owned together" ]
    ).value!
    Coordinator::Write::Operations::ExecuteCreateWorkItem.new(event_store:).call(
      command_id: "seed-create-#{RENEW_WORK_ITEM_ID}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: RENEW_CHANGE_SET_ID,
      work_item_id: RENEW_WORK_ITEM_ID,
      repository_id: "billing",
      goal: "Implement the coordinated change",
      acceptance_criteria: [ "Renewal retains every fencing identity" ]
    ).value!
    Coordinator::Write::Operations::ExecuteActivateChangeSet.new(event_store:).call(
      command_id: "seed-activate-#{RENEW_CHANGE_SET_ID}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: RENEW_CHANGE_SET_ID
    ).value!
    activation = event_store.read(
      streams.change_set(RENEW_CHANGE_SET_ID),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACQUISITION
    ).find { _1.type == "ChangeSetActivated" }
    Coordinator::Processes::ProcessManagers::ChangeSetReadiness.new(event_store:).call(activation)
    Coordinator::Write::Operations::ExecuteAcquireWorkItem.new(event_store:).call(
      command_id: "seed-acquire-#{RENEW_ATTEMPT_ID}",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: RENEW_CHANGE_SET_ID,
      work_item_id: RENEW_WORK_ITEM_ID,
      attempt_id: RENEW_ATTEMPT_ID,
      base_snapshots: [ { repository_id: "billing", commit_oid: RENEW_BASE_COMMIT_OID } ]
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

  def write_set_renewal_events
    event_store.read(
      streams.attempt(RENEW_ATTEMPT_ID),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "WriteSetRenewed" ],
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def resource_renewal_events
    %w[app/a.rb app/b.rb].flat_map do |path|
      resource = normalizer.call(repository_id: "billing", kind: "file", path:, base_blob_oid: nil).value!
      event_store.read(
        streams.resource_lease(resource.resource_key_hash),
        Coordinator::Write::EventReadCriteria.new(
          event_types: [ "ResourceLeaseRenewed" ],
          maximum_count: 10,
          direction: :asc
        )
      )
    end
  end
end
