# frozen_string_literal: true

module McpResourceResolutionSpec
  RSpec.describe "MCP server-owned Resource resolution", :event_store do
  PROTOCOL_VERSION = "2026-07-28"
  TASKS_EXTENSION = "io.modelcontextprotocol/tasks"
  RESOURCE_PATH = "app/models/account.rb"

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:repository_id) { RepositoryScenario::DEFAULT_REPOSITORY_ID }
  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end

  before { RepositoryScenario.register(event_store:) }

  it "allocates one UUIDv7, returns it on replay, and persists only server-derived identity facts" do
    first = resolve_resource(command_id: "cmd-resource-new")
    resource_id = first.dig("structuredContent", "data", "resource_id")

    expect(first).to include(
      "isError" => false,
      "structuredContent" => include(
        "status" => "ok",
        "data" => include(
          "resource_id" => a_string_matching(Coordinator::Shared::Types::UUID_V7_PATTERN),
          "repository_id" => repository_id,
          "kind" => "file",
          "normalized_path" => RESOURCE_PATH,
          "outcome" => "registered"
        )
      )
    )
    expect(resource_events(resource_id).map(&:type)).to eq(%w[ResourceRegistered ResourceBound])
    expect(resource_events(resource_id).map(&:stream_revision)).to eq([ 0, 1 ])

    existing = resolve_resource(command_id: "cmd-resource-existing")
    replayed = resolve_resource(command_id: "cmd-resource-new")

    expect(existing.dig("structuredContent", "data")).to include(
      "resource_id" => resource_id,
      "outcome" => "existing"
    )
    expect(replayed).to eq(first)
    expect(resource_events(resource_id).length).to eq(2)
    expect(command_events("cmd-resource-new").length).to eq(1)
  end

  it "converges two simultaneous MCP commands on one Resource UUID through the real serializable store" do
    submissions = distinct_lane_submissions
    commands = submissions.map(&:first)
    responses = submissions.map(&:last)
    task_ids = responses.map { _1.dig("result", "taskId") }
    submitted = task_ids.map { task_events(_1).find { |event| event.type == "CoordinationTaskSubmitted" } }
    barrier = install_contention_barrier(commands)
    errors = Queue.new

    threads = submitted.map do |event|
      Thread.new do
        Coordinator::Container["process_managers.coordination_task_executor"].call(event)
      rescue StandardError => error
        errors << error
      end
    end
    threads.each(&:join)
    raise errors.pop unless errors.empty?

    results = task_ids.map { task_request(_1).dig("result", "result") }
    resource_ids = results.map { _1.dig("structuredContent", "data", "resource_id") }

    expect(results).to all(include("isError" => false))
    expect(resource_ids.uniq.length).to eq(1)
    expect(resource_events(resource_ids.uniq.sole).map(&:type)).to eq(%w[ResourceRegistered ResourceBound])
  ensure
    ActiveSupport::Notifications.unsubscribe(barrier) if barrier
  end

  it "removes idempotently and reactivates the original UUID without another registration" do
    first = resolve_resource(command_id: "cmd-resource-lifecycle-new")
    resource_id = first.dig("structuredContent", "data", "resource_id")

    removed = remove_resource(
      command_id: "cmd-resource-lifecycle-remove",
      resource_id:,
      reason: "removed"
    )
    repeated = remove_resource(
      command_id: "cmd-resource-lifecycle-remove-again",
      resource_id:,
      reason: "removed"
    )
    reactivated = resolve_resource(command_id: "cmd-resource-lifecycle-reactivate")

    expect(removed.dig("structuredContent", "data")).to include(
      "resource_id" => resource_id,
      "outcome" => "removed",
      "reason" => "removed"
    )
    expect(repeated.dig("structuredContent", "data")).to include(
      "resource_id" => resource_id,
      "outcome" => "already_inactive"
    )
    expect(reactivated.dig("structuredContent", "data")).to include(
      "resource_id" => resource_id,
      "outcome" => "reactivated"
    )
    expect(resource_events(resource_id).map(&:type)).to eq(
      %w[ResourceRegistered ResourceBound ResourceUnbound ResourceBound]
    )
  end

  it "requires explicit removal before a kind change and gives the new tuple another UUID" do
    file = resolve_resource(
      command_id: "cmd-resource-kind-file",
      path: "docs",
      kind: "file"
    )
    file_id = file.dig("structuredContent", "data", "resource_id")

    conflict = resolve_resource(
      command_id: "cmd-resource-kind-conflict",
      path: "docs",
      kind: "directory"
    )
    remove_resource(
      command_id: "cmd-resource-kind-remove",
      resource_id: file_id,
      reason: "type_changed"
    )
    directory = resolve_resource(
      command_id: "cmd-resource-kind-directory",
      path: "docs",
      kind: "directory"
    )

    expect(conflict).to include(
      "isError" => true,
      "structuredContent" => include(
        "data" => include("code" => "resource_path_conflict")
      )
    )
    expect(directory.dig("structuredContent", "data")).to include(
      "kind" => "directory",
      "outcome" => "registered"
    )
    expect(directory.dig("structuredContent", "data", "resource_id")).not_to eq(file_id)
    expect(resource_events(file_id).map(&:type)).to eq(
      %w[ResourceRegistered ResourceBound ResourceUnbound]
    )
  end

  it "turns duplicate exact-marker registrations into a typed denial without a command fact" do
    identity = Coordinator::Write::ResourceIdentityNormalizer.new.call(
      repository_id:,
      kind: "file",
      path: RESOURCE_PATH
    ).value!
    2.times { seed_registration(identity, resource_id: SecureRandom.uuid_v7) }

    result = resolve_resource(command_id: "cmd-resource-corrupt")

    expect(result).to include(
      "isError" => true,
      "structuredContent" => include(
        "status" => "conflict",
        "data" => include(
          "code" => "resource_history_corrupt",
          "details" => include("reason" => "duplicate_registration")
        )
      )
    )
    expect(command_events("cmd-resource-corrupt")).to be_empty
  end

  private

  def resolve_resource(command_id:, path: RESOURCE_PATH, kind: "file")
    response = call_tool("resource_resolve", resource_arguments(command_id:, path:, kind:))
    execute_task(response)
  end

  def remove_resource(command_id:, resource_id:, reason:)
    response = call_tool(
      "resource_remove",
      {
        command_id:,
        actor: { kind: "agent", id: "resource-agent" },
        resource_id:,
        reason:
      }
    )
    execute_task(response)
  end

  def execute_task(response)
    expect(response["error"]).to be_nil, response.inspect
    task_id = response.dig("result", "taskId")
    submitted = task_events(task_id).find { _1.type == "CoordinationTaskSubmitted" }
    collector = ReportedErrorCollector.new
    Rails.error.subscribe(collector)
    Coordinator::Container["process_managers.coordination_task_executor"].call(submitted)
    raise collector.errors.first if collector.errors.any?

    task_request(task_id).dig("result", "result")
  ensure
    Rails.error.unsubscribe(collector) if collector
  end

  def resource_arguments(command_id:, actor_id: "resource-agent", path: RESOURCE_PATH, kind: "file")
    {
      command_id:,
      actor: { kind: "agent", id: actor_id },
      repository_id:,
      kind:,
      path:
    }
  end

  def resource_events(resource_id)
    event_store.read(
      streams.resource(resource_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[ResourceRegistered ResourceBound ResourceUnbound],
        maximum_count: 16,
        direction: :asc
      )
    )
  end

  def seed_registration(identity, resource_id:)
    payload = Coordinator::Write::Events::ResourceIdentityV1::Registered.new(
      resource_id:,
      repository_id: identity.repository_id,
      kind: identity.kind,
      normalized_path: identity.normalized_path,
      registered_at: "2026-08-28T00:00:00.000000Z"
    )
    event = Coordinator::Write::EventFactory.new.build!(
      event: payload,
      event_id: SecureRandom.uuid_v7,
      metadata: Coordinator::Write::EventMetadata.new(
        command_id: "seed-resource-#{resource_id}",
        actor_kind: "system",
        actor_id: "resource-corruption-fixture",
        recorded_by: "coordinator",
        policy_version: "resource-identity/v1"
      ),
      markers: [ identity.identity_marker, "resource:#{resource_id}" ]
    )
    event_store.append(streams.resource(resource_id), [ event ])
  end

  def distinct_lane_submissions
    lane = Coordinator::Write::Tasks::ExecutionLane.new
    by_lane = {}
    64.times do |index|
      command_id = "cmd-resource-race-#{index}"
      response = call_tool(
        "resource_resolve",
        resource_arguments(command_id:, actor_id: "agent-#{index}")
      )
      task_id = response.dig("result", "taskId")
      by_lane[lane.index(task_id)] ||= [ command_id, response ]
      break if by_lane.length == Coordinator::Write::Tasks::ExecutionLane::COUNT
    end
    by_lane.sort.map(&:last)
  end

  def install_contention_barrier(command_ids)
    mutex = Thread::Mutex.new
    condition = Thread::ConditionVariable.new
    arrivals = Set.new

    ActiveSupport::Notifications.subscribe("coordinator.command_boundary") do |_name, _start, _finish, _id, payload|
      next unless payload.fetch(:operation) == "resource_resolve_dcb"
      next unless command_ids.include?(payload.fetch(:command_id))

      mutex.synchronize do
        arrivals.add(payload.fetch(:command_id))
        condition.broadcast
        condition.wait(mutex) until arrivals.length == command_ids.length
      end
    end
  end

  def call_tool(name, arguments)
    mcp_request(method: "tools/call", name:, params: { name:, arguments: })
  end

  def task_request(task_id)
    mcp_request(method: "tasks/get", name: task_id, params: { taskId: task_id })
  end

  def mcp_request(method:, name:, params:)
    session.post(
      "/mcp",
      params: JSON.generate(jsonrpc: "2.0", id: SecureRandom.random_number(1_000_000), method:, params: modern_params(params)),
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

  def modern_params(params)
    params.merge(
      _meta: {
        "io.modelcontextprotocol/protocolVersion" => PROTOCOL_VERSION,
        "io.modelcontextprotocol/clientCapabilities" => {
          extensions: { TASKS_EXTENSION => {} }
        },
        "io.modelcontextprotocol/clientInfo" => { name: "rspec", version: "1.0" }
      }
    )
  end

  def task_events(task_id)
    event_store.read(streams.coordination_task(task_id), Coordinator::Write::EventQueries::COORDINATION_TASK_HISTORY)
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_COMPLETION)
  end
  end
end
