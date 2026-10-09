# frozen_string_literal: true

RSpec.describe "CAN-01 MCP Candidate coordination" do
  CANDIDATE_PROTOCOL_VERSION = "2026-07-28"
  CANDIDATE_TASKS_EXTENSION = "io.modelcontextprotocol/tasks"

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end

  it "submits a traced Candidate Task", :event_store do
    prepared = CandidateScenario.prepare(prefix: "mcp-candidate")
    arguments = prepared.fetch(:input).merge(
      build_context: CandidateScenario.build_context_for("lib/candidate.rb")
    )

    created = call_tool("candidate_submit", arguments, id: 1)
    expect(created).to include("result" => include("taskId" => a_string_matching(
      Coordinator::Shared::Types::UUID_V7_PATTERN
    )))
    task_id = created.dig("result", "taskId")
    expect(task_events(task_id).map(&:type)).to eq([ "CoordinationTaskSubmitted" ])

    execute_task(task_id)
    completed = task_request("tasks/get", task_id, id: 2)
    result = completed.dig("result", "result", "structuredContent")
    expect(completed.dig("result", "status")).to eq("completed")
    expect(result).to include(
      "status" => "ok",
      "command_id" => "cmd-mcp-candidate",
      "data" => include(
        "candidate_id" => "CAN-mcp-candidate",
        "evidence_status" => "attributed_unverified",
        "head_commit_oid" => "b" * 40
      )
    )

    submitted, started, task_completed = task_events(task_id)
    candidate_facts = CandidateScenario.candidate_events("CAN-mcp-candidate")
    command_terminal = command_events_for_task(task_id).last
    expect(candidate_facts.map(&:type)).to eq(%w[
      CandidateCreated
      CandidateAssignedToAttempt
      CandidateAssignedToRepository
      CandidateTargetBranchSelected
      CandidateCommitRangeDeclared
      CandidateCheckpointKindSelected
      CandidateWorkIntentionSetAssigned
      CandidateChangeManifestCaptured
      CandidateBuildContextCaptured
      CandidateSubmitted
    ])
    expect(candidate_facts.map(&:causation_id).uniq).to eq([ started.id ])
    command_facts = CommandTraceFixture.domain_events(task_id, event_store:)
    expect(command_facts.map(&:causation_id).uniq).to eq([ started.id ])
    expect(command_terminal.causation_id).to eq(command_facts.last.id)
    expect(task_completed.causation_id).to eq(command_terminal.id)
    expect([ submitted, started, *candidate_facts, command_terminal, task_completed ].map(&:correlation_id).uniq).to eq(
      [ submitted.correlation_id ]
    )
  end

  it "serves directly persisted partial and complete Candidate views", :read_model do
    create(
      :coordinator_read_candidate,
      candidate_id: "CAN-mcp-candidate-partial",
      submitted_causation_id: SecureRandom.uuid_v7,
      submitted_correlation_id: SecureRandom.uuid_v7
    )
    partial = call_tool("candidate_get", { candidate_id: "CAN-mcp-candidate-partial" }, id: 3)
      .dig("result", "structuredContent")
    expect(partial).to include(
      "status" => "ok",
      "data" => include(
        "candidate" => include(
          "candidate_id" => "CAN-mcp-candidate-partial",
          "manifest" => nil,
          "build_context" => nil,
          "submitted" => include(
            "causation_id" => a_string_matching(Coordinator::Shared::Types::UUID_V7_PATTERN),
            "correlation_id" => a_string_matching(Coordinator::Shared::Types::UUID_V7_PATTERN)
          )
        )
      )
    )

    create(
      :coordinator_read_candidate,
      :manifest_observed,
      :build_context_observed,
      candidate_id: "CAN-mcp-candidate",
      attempt_id: "A-mcp-candidate"
    )
    full = call_tool("candidate_get", { candidate_id: "CAN-mcp-candidate" }, id: 4)
      .dig("result", "structuredContent", "data", "candidate")
    expect(full).to include(
      "evidence_status" => "attributed_unverified",
      "manifest" => include("digest" => full.fetch("manifest_digest")),
      "build_context" => include("digest" => full.fetch("build_context_digest"))
    )
    expect(full.keys & %w[fresh pending projection_status]).to be_empty

    page = call_tool(
      "candidate_list",
      { attempt_id: "A-mcp-candidate", limit: 20 },
      id: 5
    ).dig("result", "structuredContent", "data", "page")
    expect(page).to include("has_more" => false, "next_global_position" => nil)
    expect(page.fetch("items").sole).to include(
      "candidate_id" => "CAN-mcp-candidate",
      "manifest_observed" => true,
      "build_context_observed" => true
    )
  end

  it "completes a stale work-intention Task as a conflict without target facts", :event_store do
    prepared = CandidateScenario.prepare(prefix: "mcp-candidate-stale")
    arguments = prepared.fetch(:input)
    arguments[:intentions] = arguments.fetch(:intentions).map do |intention|
      intention.merge(fencing_token: intention.fetch(:fencing_token) + 1)
    end

    created = call_tool("candidate_submit", arguments, id: 1)
    expect(created).to include("result" => include("taskId" => a_string_matching(
      Coordinator::Shared::Types::UUID_V7_PATTERN
    )))
    task_id = created.dig("result", "taskId")
    execute_task(task_id)
    completed = task_request("tasks/get", task_id, id: 2)

    expect(completed.dig("result", "status")).to eq("completed")
    expect(completed.dig("result", "result")).to include(
      "isError" => true,
      "structuredContent" => include(
        "status" => "conflict",
        "data" => include("code" => "work_intention_observations_mismatch")
      )
    )
    expect(CandidateScenario.candidate_events("CAN-mcp-candidate-stale")).to be_empty
    expect(command_events("cmd-mcp-candidate-stale")).to be_empty
  end

  it "completes a withdrawn-intention Candidate Task without fabricating a withdrawal timestamp", :event_store do
    arguments = CandidateScenario.prepare(prefix: "mcp-candidate-withdrawn").fetch(:input)
    CandidateScenario.execute(
      Coordinator::Write::Operations::ExecuteWithdrawWorkIntentionSet,
      arguments.slice(:actor, :change_set_id, :work_item_id, :attempt_id, :intention_set_id, :intentions)
        .merge(command_id: "cmd-withdraw-before-candidate")
    )
    task_id = call_tool("candidate_submit", arguments, id: 1).dig("result", "taskId")
    execute_task(task_id)
    completed = task_request("tasks/get", task_id, id: 2)
    result = completed.dig("result", "result")

    expect(completed.dig("result", "status")).to eq("completed")
    expect(result.fetch("isError")).to be(true)
    expect(result.dig("structuredContent", "data", "code")).to eq("work_intention_set_withdrawn")
    details = result.dig("structuredContent", "data", "details")
    expect(details).to include("attempt_id" => arguments.fetch(:attempt_id))
    expect(details).not_to have_key("withdrawn_at")
    expect(CandidateScenario.candidate_events(arguments.fetch(:candidate_id))).to be_empty
  end

  it "rejects malformed evidence before allocating a Task", :event_store do
    arguments = CandidateScenario.prepare(prefix: "mcp-candidate-invalid").fetch(:input)
    arguments[:intentions] = []

    response = call_tool("candidate_submit", arguments, id: 1)

    expect(response.dig("result")).to include(
      "isError" => true,
      "content" => [ include("text" => include("array size at `/intentions` is less than: 1")) ]
    )
    expect(task_events_for_command("cmd-mcp-candidate-invalid")).to be_empty
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
        "MCP-Protocol-Version" => CANDIDATE_PROTOCOL_VERSION,
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
        "io.modelcontextprotocol/protocolVersion" => CANDIDATE_PROTOCOL_VERSION,
        "io.modelcontextprotocol/clientCapabilities" => {
          extensions: { CANDIDATE_TASKS_EXTENSION => {} }
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

  def command_events_for_task(task_id)
    task = Coordinator::Write::Tasks::Loader.new(event_store:).call(task_id).state
    event_store.read(
      streams.command(task.command_id),
      Coordinator::Write::EventQueries::COMMAND_HISTORY
    )
  end
end
