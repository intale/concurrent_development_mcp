# frozen_string_literal: true

RSpec.describe "D-053 MCP Tasks walking slice", :event_store, :read_model do
  PROTOCOL_VERSION = "2026-07-28"
  TASKS_EXTENSION = "io.modelcontextprotocol/tasks"

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end

  it "advertises mandatory Tasks and lists only the accepted application tools" do
    discovered = mcp_request(
      id: 1,
      method: "server/discover",
      params: {},
      capable: false
    )

    expect(discovered.dig("result", "supportedVersions")).to include(PROTOCOL_VERSION)
    expect(
      discovered.dig("result", "capabilities", "extensions", TASKS_EXTENSION)
    ).to eq({})

    listed = mcp_request(id: 2, method: "tools/list", params: {})
    tools = listed.dig("result", "tools")
    expect(tools.map { _1.fetch("name") }).to contain_exactly(
      "coord_context",
      "attempt_list",
      "operation_get",
      "guidance_get",
      "decision_interpretation_list",
      "decision_get",
      "decision_resolve",
      "agent_choice_get",
      "agent_choice_impact_list",
      "attempt_abandon",
      "candidate_get",
      "candidate_list",
      "candidate_impact_get",
      "repository_list",
      "skill_get",
      "skill_list",
      "skill_asset_get",
      "development_artifact_get",
      "development_artifact_content_get",
      "development_artifact_relation_list",
      "development_artifact_locator_resolve",
      "development_artifact_list",
      "operation_batch_get",
      "verification_obligations_list",
      "merge_snapshot_get",
      "repository_register",
      "decision_interpretation_adjudicate",
      "decision_activate",
      "decision_correct",
      "agent_choice_record",
      "candidate_submit",
      "candidate_impact_surface_submit",
      "verification_obligation_claim",
      "verification_obligation_waive",
      "compatibility_assessment_submit",
      "merge_snapshot_register",
      "merge_verification_submit",
      "merge_authorization_request",
      "merge_observation_record",
      "release_set_get",
      "release_set_prepare",
      "release_repository_integration_record",
      "release_verification_record",
      "release_activation_record",
      "release_compensation_complete",
      "skill_publish",
      "skill_publish_batch",
      "development_artifact_capture",
      "development_artifact_capture_batch",
      "development_artifact_relation_declare",
      "development_artifact_relation_declare_batch",
      "operation_batch_cancel",
      "change_set_create",
      "work_item_create",
      "work_item_dependency_declare",
      "change_set_activate",
      "work_item_acquire",
      "work_item_complete",
      "write_set_reserve",
      "write_set_expand",
      "lease_renew",
      "lease_release",
      "guidance_record",
      "decision_interpretation_propose"
    )
    expect(tools.find { _1.fetch("name") == "operation_get" }.fetch("annotations")).to include(
      "readOnlyHint" => true,
      "idempotentHint" => true,
      "openWorldHint" => false
    )
    expect(tools.find { _1.fetch("name") == "change_set_create" }.fetch("annotations")).to include(
      "readOnlyHint" => false,
      "idempotentHint" => true,
      "destructiveHint" => false
    )
    expect(tools.find { _1.fetch("name") == "attempt_abandon" }.fetch("annotations")).to include(
      "readOnlyHint" => false,
      "idempotentHint" => true,
      "destructiveHint" => false
    )
  end

  it "registers one exact scoped UUIDv7 repository through a replayable durable Task" do
    repository_id = SecureRandom.uuid_v7
    arguments = {
      command_id: "cmd-mcp-repository-register",
      actor: { kind: "agent", id: "planner-repository" },
      repository_id:,
      scope: "project:payments/workspace:primary",
      repository_key: "payments",
      display_name: "Payments API",
      paths: [ "/client-visible/payments", "/other-container/payments" ],
      remotes: [ "https://example.test/payments.git" ]
    }

    submitted = call_tool("repository_register", arguments, id: 1)
    task_id = submitted.dig("result", "taskId")
    expect(task_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN), submitted.inspect
    execute_task(task_id)
    completed = task_request("tasks/get", task_id:, id: 2)
    result = completed.dig("result", "result")

    expect(completed.dig("result", "status")).to eq("completed"), completed.inspect
    expect(result).to include(
      "isError" => false,
      "structuredContent" => include(
        "status" => "ok",
        "data" => include(
          "repository_id" => repository_id,
          "scope" => "project:payments/workspace:primary",
          "paths" => arguments.fetch(:paths),
          "remotes" => arguments.fetch(:remotes)
        )
      )
    )
    registration = repository_events(repository_id).sole
    expect(registration.type).to eq("RepositoryRegistered")
    expect(registration.markers).to include("repository:#{repository_id}")
    expect(
      registration.markers.grep(
        /\Acompound:(?:repository-scope|scoped-repository|scoped-repository-key):v1:/
      ).length
    ).to eq(3)
    expect(registration.metadata).not_to have_key("correlation_id")

    Coordinator::Container["projectors.repositories_v1"].call(registration)
    projected = call_tool(
      "repository_list",
      {
        scope: arguments.fetch(:scope),
        repository_key: arguments.fetch(:repository_key),
        limit: 20
      },
      id: 8
    ).dig("result", "structuredContent")
    expect(projected).to include("status" => "ok")
    expect(projected.dig("data", "page", "items").sole).to include(
      "repository_id" => repository_id,
      "scope" => arguments.fetch(:scope),
      "paths" => arguments.fetch(:paths),
      "remotes" => arguments.fetch(:remotes)
    )
    expect(JSON.generate(projected)).not_to include("projection_status", "pending")

    replay_task_id = call_tool("repository_register", arguments, id: 3).dig("result", "taskId")
    execute_task(replay_task_id)
    replay = task_request("tasks/get", task_id: replay_task_id, id: 4)
    expect(replay.dig("result", "result")).to eq(result)
    expect(repository_events(repository_id).length).to eq(1)
    expect(command_events(arguments.fetch(:command_id)).length).to eq(1)

    conflict_task_id = call_tool(
      "repository_register",
      arguments.merge(command_id: "cmd-mcp-repository-conflict", scope: "project:other"),
      id: 5
    ).dig("result", "taskId")
    execute_task(conflict_task_id)
    denied = task_request("tasks/get", task_id: conflict_task_id, id: 6)
    expect(denied.dig("result", "status")).to eq("completed"), denied.inspect
    expect(denied.dig("result", "result")).to include(
      "isError" => true,
      "structuredContent" => include(
        "status" => "conflict",
        "data" => include("code" => "repository_identity_conflict")
      )
    )
    expect(repository_events(repository_id).length).to eq(1)
    expect(command_events("cmd-mcp-repository-conflict")).to be_empty

    invalid = call_tool(
      "repository_register",
      arguments.merge(command_id: "cmd-mcp-repository-invalid", repository_id: "payments"),
      id: 7
    )
    expect(invalid.dig("result", "resultType")).to eq("complete")
    expect(invalid.dig("result", "isError")).to be(true)
    expect(task_events_for_command("cmd-mcp-repository-invalid")).to be_empty
  end

  it "teaches a clean agent to migrate client-visible development memory semantically" do
    discovered = mcp_request(
      id: 1,
      method: "server/discover",
      params: {},
      capable: false
    )
    instructions = discovered.dig("result", "instructions").squish

    expect(instructions).to include(
      "inspect that project with the client's own available capabilities",
      "never by a server-prescribed directory layout",
      "The coordinator cannot read caller paths",
      "capture an import_manifest last"
    )

    tools = mcp_request(id: 2, method: "tools/list", params: {}).dig("result", "tools")
    artifact = tools.find { _1.fetch("name") == "development_artifact_capture" }
    artifact_batch = tools.find { _1.fetch("name") == "development_artifact_capture_batch" }
    skill = tools.find { _1.fetch("name") == "skill_publish" }
    relation = tools.find { _1.fetch("name") == "development_artifact_relation_declare" }

    expect(artifact.fetch("description")).to include("project it can inspect", "exact bytes")
    expect(artifact_batch.fetch("description")).to include("server assumes no project path layout")
    expect(skill.fetch("description")).to include("caller-discovered reusable instruction set")
    expect(relation.fetch("description")).to include("caller")

    artifact_schema = artifact.fetch("inputSchema")
    expect(artifact_schema.dig("properties", "kind", "description")).to include(
      "choose from meaning, not filename or directory alone"
    )
    expect(artifact_schema.dig("properties", "content", "properties", "text", "description")).to include(
      "do not send a filesystem path"
    )
    expect(artifact_schema.dig("properties", "source", "properties", "locator", "description")).to include(
      "server never dereferences it"
    )
    expect(skill.dig("inputSchema", "properties", "scope", "description")).to include(
      "server infers no scope hierarchy"
    )

    reusable_surface = JSON.generate(
      tools.select do |tool|
        %w[
          skill_publish skill_publish_batch development_artifact_capture
          development_artifact_capture_batch development_artifact_relation_declare
          development_artifact_relation_declare_batch
        ].include?(tool.fetch("name"))
      end
    )
    expect(reusable_surface).not_to include(".build", ".to_review", "source_root", "Rails.root")
  end

  it "submits, polls, executes, replays, and independently projects one mutation" do
    arguments = {
      command_id: "cmd-mcp-task-100",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-MCP-TASK-100",
      goal: "Coordinate repositories",
      acceptance_criteria: [ "Agents do not overlap" ]
    }

    created = call_tool("change_set_create", arguments, id: 1)
    task_id = created.dig("result", "taskId")

    expect(created.fetch("result")).to include(
      "resultType" => "task",
      "status" => "working",
      "taskId" => task_id,
      "ttlMs" => nil,
      "pollIntervalMs" => 500
    )
    expect(task_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN), created.inspect
    expect(task_events(task_id).map(&:type)).to eq([ "CoordinationTaskSubmitted" ])
    expect(command_events(arguments.fetch(:command_id))).to be_empty
    expect(change_set_events(arguments.fetch(:change_set_id))).to be_empty

    working = task_request("tasks/get", task_id:, id: 2)
    expect(working.fetch("result")).to include(
      "resultType" => "complete",
      "status" => "working",
      "taskId" => task_id
    )

    execute_task(task_id)
    completed = task_request("tasks/get", task_id:, id: 3)
    tool_result = completed.dig("result", "result")
    expect(completed.fetch("result")).to include(
      "resultType" => "complete",
      "status" => "completed",
      "taskId" => task_id
    )
    expect(tool_result).to include(
      "isError" => false,
      "structuredContent" => include(
        "status" => "ok",
        "command_id" => arguments.fetch(:command_id),
        "receipt" => arguments.fetch(:command_id)
      )
    )
    expect(JSON.parse(tool_result.fetch("content").sole.fetch("text"))).to eq(
      tool_result.fetch("structuredContent")
    )

    replay = call_tool("change_set_create", arguments, id: 4)
    replay_task_id = replay.dig("result", "taskId")
    expect(replay_task_id).not_to eq(task_id)
    execute_task(replay_task_id)
    replayed = task_request("tasks/get", task_id: replay_task_id, id: 5)
    expect(replayed.dig("result", "result")).to eq(tool_result)
    expect(command_events(arguments.fetch(:command_id)).length).to eq(1)
    expect(change_set_events(arguments.fetch(:change_set_id)).length).to eq(2)

    absent = call_tool("operation_get", { command_id: arguments.fetch(:command_id) }, id: 6)
    expect(absent.dig("result", "resultType")).to eq("complete")
    expect(absent.dig("result", "structuredContent", "status")).to eq("not_found")

    Coordinator::Read::Projectors::CommandReceiptsV1.new.call(
      command_events(arguments.fetch(:command_id)).sole
    )
    current = call_tool("operation_get", { command_id: arguments.fetch(:command_id) }, id: 7)
    expect(current.dig("result", "structuredContent", "status")).to eq("ok")

    projector = Coordinator::Read::Projectors::CoordContextV1.new
    change_set_events(arguments.fetch(:change_set_id)).each { projector.call(_1) }
    context = call_tool(
      "coord_context",
      { change_set_id: arguments.fetch(:change_set_id) },
      id: 8
    )
    context_payload = context.dig("result", "structuredContent")
    expect(context_payload).to include("status" => "ok")
    expect(context_payload).not_to have_key("projection_status")
    expect(context_payload.dig("data", "context", "change_set", "goal")).to eq(
      "Coordinate repositories"
    )
  end

  it "completes a WorkItem through a durable Task after its final Candidate relinquishes leases" do
    collector = ReportedErrorCollector.new
    Rails.error.subscribe(collector)
    candidate = CandidateScenario.submit(prefix: "mcp-complete")
    CandidateScenario.release(candidate)
    arguments = CandidateScenario.completion_input(
      candidate,
      command_id: "cmd-mcp-work-item-complete",
      produced_outputs: [ { kind: "contract", key: "payments-v2" } ]
    )

    submitted = call_tool("work_item_complete", arguments, id: 1)
    raise collector.errors.first if collector.errors.any?
    task_id = submitted.dig("result", "taskId")
    expect(task_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN), submitted.inspect

    execute_task(task_id)
    completed = task_request("tasks/get", task_id:, id: 2)

    expect(completed.dig("result", "status")).to eq("completed")
    expect(completed.dig("result", "result", "isError")).to be(false), completed.inspect
    expect(completed.dig("result", "result", "structuredContent", "data")).to include(
      "work_item_id" => candidate.dig(:ids, :work_item_id),
      "attempt_id" => candidate.dig(:ids, :attempt_id),
      "candidate_id" => candidate.dig(:input, :candidate_id),
      "produced_outputs" => [ { "kind" => "contract", "key" => "payments-v2" } ]
    )
    expect(command_events(arguments.fetch(:command_id)).map(&:type)).to eq([ "CommandCompleted" ])
  ensure
    Rails.error.unsubscribe(collector) if collector
  end

  it "runs merge snapshot registration as a durable Task and serves its lagging projection" do
    candidate = CandidateScenario.submit(prefix: "mcp-merge-snapshot", build_context: false)
    arguments = {
      command_id: "cmd-mcp-merge-snapshot-register",
      actor: { kind: "agent", id: "integrator-1" },
      merge_snapshot_id: "MS-mcp-merge-snapshot",
      repository_id: candidate.dig(:input, :repository_id),
      target_branch: "main",
      target_base_commit_oid: "a" * 40,
      ordered_candidates: [
        {
          candidate_id: candidate.dig(:input, :candidate_id),
          head_commit_oid: candidate.dig(:input, :head_commit_oid)
        }
      ],
      merge_commit_oid: "9" * 40,
      producer: { name: "git-merge", version: "2.47.0" },
      run_id: "run-mcp-merge-snapshot",
      produced_at: "2026-08-24T15:30:00.000001Z"
    }

    submitted = call_tool("merge_snapshot_register", arguments, id: 1)
    task_id = submitted.dig("result", "taskId")
    expect(task_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    execute_task(task_id)
    state = task_request("tasks/get", task_id:, id: 2)
    expect(state.dig("result", "status")).to eq("completed")
    expect(state.dig("result", "result", "isError")).to be(false)
    expect(state.dig("result", "result", "structuredContent", "data")).to include(
      "merge_snapshot_id" => arguments.fetch(:merge_snapshot_id),
      "evidence_status" => "attributed_unverified"
    )

    unavailable = call_tool(
      "merge_snapshot_get",
      { merge_snapshot_id: arguments.fetch(:merge_snapshot_id) },
      id: 3
    )
    expect(unavailable.dig("result", "structuredContent", "status")).to eq("not_found")

    snapshot = event_store.read(
      streams.merge_snapshot(arguments.fetch(:merge_snapshot_id)),
      Coordinator::Write::EventQueries::MERGE_SNAPSHOT_REGISTRATION
    ).sole
    Coordinator::Container["projectors.merge_snapshots_v1"].call(snapshot)
    available = call_tool(
      "merge_snapshot_get",
      { merge_snapshot_id: arguments.fetch(:merge_snapshot_id) },
      id: 4
    )
    expect(available.dig("result", "structuredContent", "data", "snapshot")).to include(
      "merge_snapshot_id" => arguments.fetch(:merge_snapshot_id),
      "evidence_status" => "attributed_unverified"
    )
  end

  it "requests merge authorization as a durable Task against authoritative event facts" do
    registration = MergeSnapshotScenario.register(prefix: "mcp-merge-authorization")
    verification = MergeSnapshotScenario.verify(
      registration,
      prefix: "mcp-merge-authorization"
    )
    arguments = MergeSnapshotScenario.authorization_input(
      registration,
      verification,
      prefix: "mcp-merge-authorization"
    )

    submitted = call_tool("merge_authorization_request", arguments, id: 1)
    task_id = submitted.dig("result", "taskId")
    expect(task_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)

    execute_task(task_id)
    completed = task_request("tasks/get", task_id:, id: 2)
    result = completed.dig("result", "result")

    expect(completed.dig("result", "status")).to eq("completed")
    expect(result.fetch("isError")).to be(false)
    expect(result.dig("structuredContent", "data")).to include(
      "merge_snapshot_id" => registration.dig(:input, :merge_snapshot_id),
      "outcome" => "granted"
    )
  end

  it "records an exact external merge observation through a durable Task" do
    registration = MergeSnapshotScenario.register(prefix: "mcp-merge-observation")
    verification = MergeSnapshotScenario.verify(registration, prefix: "mcp-merge-observation")
    authorization = MergeSnapshotScenario.authorize(
      registration,
      verification,
      prefix: "mcp-merge-observation"
    )
    arguments = MergeSnapshotScenario.observation_input(
      registration,
      authorization,
      prefix: "mcp-merge-observation"
    )

    submitted = call_tool("merge_observation_record", arguments, id: 1)
    task_id = submitted.dig("result", "taskId")
    expect(task_id).to be_present, submitted.inspect
    execute_task(task_id)
    completed = task_request("tasks/get", task_id:, id: 2)

    expect(completed.dig("result", "status")).to eq("completed")
    expect(completed.dig("result", "result", "isError")).to be(false)
    expect(completed.dig("result", "result", "structuredContent", "data")).to include(
      "merge_snapshot_id" => registration.dig(:input, :merge_snapshot_id),
      "target_after_commit_oid" => registration.dig(:input, :merge_commit_oid),
      "evidence_status" => "attributed_unverified"
    )
  end

  it "completes a domain denial as a tool error instead of failing the Task" do
    created = call_tool(
      "work_item_create",
      {
        command_id: "cmd-task-denied",
        actor: { kind: "agent", id: "planner-1" },
        change_set_id: "CS-missing",
        work_item_id: "W-100",
        repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
        goal: "Implement billing",
        acceptance_criteria: [ "Verified" ]
      },
      id: 1
    )
    task_id = created.dig("result", "taskId")

    execute_task(task_id)
    denied = task_request("tasks/get", task_id:, id: 2)

    expect(denied.dig("result", "status")).to eq("completed")
    expect(denied.dig("result", "result", "isError")).to be(true)
    expect(denied.dig("result", "result", "structuredContent", "status")).to eq("denied")
    expect(denied.dig("result", "result", "structuredContent", "data", "code")).to eq(
      "change_set_not_found"
    )
    expect(command_events("cmd-task-denied")).to be_empty
  end

  it "acknowledges input, cooperatively cancels queued work, and skips execution" do
    created = call_tool(
      "change_set_create",
      {
        command_id: "cmd-task-cancel",
        actor: { kind: "agent", id: "planner-1" },
        change_set_id: "CS-task-cancel",
        goal: "Cancel before execution",
        acceptance_criteria: [ "No target facts are written" ]
      },
      id: 1
    )
    task_id = created.dig("result", "taskId")

    updated = task_request(
      "tasks/update",
      task_id:,
      id: 2,
      params: { inputResponses: { ignored: { action: "accept" } } }
    )
    cancelled = task_request("tasks/cancel", task_id:, id: 3)
    expect(updated.fetch("result")).to eq("resultType" => "complete")
    expect(cancelled.fetch("result")).to eq("resultType" => "complete")

    state = task_request("tasks/get", task_id:, id: 4)
    expect(state.fetch("result")).to include(
      "status" => "cancelled",
      "statusMessage" => "Cancelled before execution"
    )

    execute_task(task_id)
    expect(command_events("cmd-task-cancel")).to be_empty
    expect(change_set_events("CS-task-cancel")).to be_empty
  end

  it "rejects clients without Tasks and validates Task handles and routing headers" do
    arguments = {
      command_id: "cmd-task-capability",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-task-capability",
      goal: "Require Tasks",
      acceptance_criteria: [ "No synchronous fallback exists" ]
    }
    missing = call_tool(
      "change_set_create",
      arguments,
      id: 1,
      capable: false
    )

    expect(missing.dig("error", "code")).to eq(-32_003)
    expect(missing.dig("error", "data", "requiredCapabilities", "extensions")).to eq(
      TASKS_EXTENSION => {}
    )
    expect(task_events_for_command(arguments.fetch(:command_id))).to be_empty

    query_without_tasks = call_tool(
      "operation_get",
      { command_id: arguments.fetch(:command_id) },
      id: 9,
      capable: false
    )
    expect(query_without_tasks.dig("error", "code")).to eq(-32_003)

    unknown_id = "02919191-9191-7191-8191-919191919191"
    unknown = task_request(
      "tasks/get",
      task_id: unknown_id,
      id: 2,
      expected_status: 400
    )
    expect(unknown.dig("error", "code")).to eq(-32_602)

    task_capability = task_request(
      "tasks/get",
      task_id: unknown_id,
      id: 3,
      capable: false
    )
    expect(task_capability.dig("error", "code")).to eq(-32_003)

    missing_name = task_request(
      "tasks/get",
      task_id: unknown_id,
      id: 4,
      include_name: false,
      expected_status: 400
    )
    expect(missing_name.dig("error", "code")).to eq(-32_020)
  end

  it "retains MCP host protection" do
    hostile = ActionDispatch::Integration::Session.new(Rails.application)
    hostile.host! "attacker.example"
    hostile.post(
      "/mcp",
      params: JSON.generate(
        jsonrpc: "2.0",
        id: 1,
        method: "tools/list",
        params: modern_params({})
      ),
      headers: request_headers(method: "tools/list")
    )

    expect(hostile.response.status).to eq(403)
  end

  def call_tool(name, arguments, id:, capable: true)
    mcp_request(
      id:,
      method: "tools/call",
      params: { name:, arguments: },
      capable:,
      name:
    )
  end

  def task_request(
    method,
    task_id:,
    id:,
    params: {},
    capable: true,
    include_name: true,
    expected_status: 200
  )
    mcp_request(
      id:,
      method:,
      params: params.merge(taskId: task_id),
      capable:,
      name: include_name ? task_id : nil,
      expected_status:
    )
  end

  def mcp_request(
    id:,
    method:,
    params:,
    capable: true,
    name: nil,
    envelope: true,
    expected_status: 200
  )
    request_params = envelope ? modern_params(params, capable:) : params
    session.post(
      "/mcp",
      params: JSON.generate(jsonrpc: "2.0", id:, method:, params: request_params),
      headers: request_headers(method:, name:)
    )
    expect(session.response.status).to eq(expected_status), session.response.body
    JSON.parse(session.response.body)
  end

  def modern_params(params, capable: true)
    capabilities = capable ? { extensions: { TASKS_EXTENSION => {} } } : {}
    params.merge(
      _meta: {
        "io.modelcontextprotocol/protocolVersion": PROTOCOL_VERSION,
        "io.modelcontextprotocol/clientCapabilities": capabilities,
        "io.modelcontextprotocol/clientInfo": { name: "rspec", version: "1.0" }
      }
    )
  end

  def request_headers(method:, name: nil)
    {
      "Content-Type" => "application/json",
      "Accept" => "application/json, text/event-stream",
      "MCP-Protocol-Version" => PROTOCOL_VERSION,
      "Mcp-Method" => method,
      "Mcp-Name" => name
    }.compact
  end

  def execute_task(task_id)
    submitted = task_events(task_id).find { _1.type == "CoordinationTaskSubmitted" }
    Coordinator::Container["process_managers.coordination_task_executor"].call(submitted)
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
            {
              type: "CoordinationTaskSubmitted",
              markers: [ "command:#{command_id}" ]
            }
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

  def change_set_events(change_set_id)
    event_store.read(
      streams.change_set(change_set_id),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACTIVATION
    )
  end

  def repository_events(repository_id)
    event_store.read(
      streams.repository(repository_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "RepositoryRegistered" ],
        maximum_count: 2,
        direction: :asc
      )
    )
  end
end
