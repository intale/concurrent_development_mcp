# frozen_string_literal: true

module McpAcceptanceWorld
  PROTOCOL_VERSION = "2026-07-28"
  TASKS_EXTENSION = "io.modelcontextprotocol/tasks"

  def tasks_capable=(value)
    @tasks_capable = value
  end

  def tasks_capable?
    @tasks_capable != false
  end

  def call_tool(name, arguments)
    mcp_request(
      method: "tools/call",
      params: { name:, arguments: },
      name:
    )
  end

  def task_request(method, task_id, params = {})
    mcp_request(
      method:,
      params: params.merge(taskId: task_id),
      name: task_id
    )
  end

  def mcp_request(method:, params:, name: nil)
    mcp_session.post(
      "/mcp",
      params: JSON.generate(
        jsonrpc: "2.0",
        id: next_request_id,
        method:,
        params: modern_params(params)
      ),
      headers: request_headers(method:, name:)
    )
    assert_acceptance(
      mcp_session.response.status == 200,
      "Expected HTTP 200, got #{mcp_session.response.status}: #{mcp_session.response.body}"
    )
    JSON.parse(mcp_session.response.body)
  end

  def execute_task(task_id)
    submitted = task_events(task_id).find { _1.type == "CoordinationTaskSubmitted" }
    assert_acceptance(submitted, "Task #{task_id} has no persisted submission")
    Coordinator::Container["process_managers.coordination_task_executor"].call(submitted)
  end

  def submit_and_execute(tool, **arguments)
    task_id = call_tool(tool, arguments).dig("result", "taskId")
    assert_acceptance(task_id, "#{tool} did not return a Task handle")
    execute_task(task_id)
    task_id
  end

  def project_change_set(change_set_id)
    projector = Coordinator::Container["projectors.coord_context_v1"]
    change_set_events(change_set_id).each { projector.call(_1) }
  end

  def project_attempt_context(change_set_id:, work_item_id:, attempt_id:)
    projector = Coordinator::Container["projectors.coord_context_v1"]
    planning = change_set_events(change_set_id)
    work = work_item_events(work_item_id)
    planning.first(2).each { projector.call(_1) }
    projector.call(work.first)
    planning.drop(2).each { projector.call(_1) }
    work.drop(1).each { projector.call(_1) }
    attempt_events(attempt_id).each { projector.call(_1) }
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

  def work_item_events(work_item_id)
    event_store.read(
      streams.work_item(work_item_id),
      Coordinator::Write::EventQueries::WORK_ITEM_FOR_ACQUISITION
    )
  end

  def attempt_events(attempt_id)
    event_store.read(
      streams.attempt(attempt_id),
      Coordinator::Write::EventQueries::ATTEMPT_FOR_WRITE_SET_EXPANSION
    )
  end

  def write_set_events(attempt_id)
    attempt_events(attempt_id).select { _1.type == "WriteSetReserved" }
  end

  def write_set_expansion_events(attempt_id)
    attempt_events(attempt_id).select { _1.type == "WriteSetExpanded" }
  end

  def write_set_renewal_events(attempt_id)
    event_store.read(
      streams.attempt(attempt_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "WriteSetRenewed" ],
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def write_set_release_events(attempt_id)
    event_store.read(
      streams.attempt(attempt_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "WriteSetReleased" ],
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def guidance_events(conversation_id)
    event_store.read(
      streams.conversation(conversation_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: Coordinator::Write::EventQueries::GUIDANCE_MESSAGE_EVENT_TYPES,
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def project_guidance(conversation_id)
    projector = Coordinator::Container["projectors.user_utterances_v1"]
    guidance_events(conversation_id).each { projector.call(_1) }
  end

  def interpretation_events(message_id)
    event_store.read(
      streams.interpretation(message_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[
          DecisionInterpretationProposed
          DecisionClarificationRequired
          DecisionInterpretationAccepted
          DecisionInterpretationRejected
        ],
        maximum_count: 100,
        direction: :asc
      )
    )
  end

  def project_interpretations(message_id)
    projector = Coordinator::Container["projectors.decision_interpretations_v1"]
    interpretation_events(message_id).each { projector.call(_1) }
  end

  def interpretation_page(message_id)
    call_tool(
      "decision_interpretation_list",
      { message_id:, after_revision: -1, limit: 20 }
    ).dig("result", "structuredContent", "data", "page", "interpretations")
  end

  def interpretation_adjudication_arguments(command_id:, interpretation_id:, action:, clarification: nil)
    {
      command_id:,
      actor: { kind: "orchestrator", id: "guidance-host" },
      source_message_id: @interpretation_message_id,
      interpretation_id:,
      action:,
      rationale: {
        code: action == "reject" ? "user_rejected" : "user_confirmed",
        summary: action == "reject" ? "The reading is not intended." : "The host assessed the proposed reading."
      },
      clarification:
    }
  end

  def lease_events(path)
    resource = Coordinator::Write::FileResourceNormalizer.new.call(
      repository_id: "billing",
      kind: "file",
      path:,
      base_blob_oid: nil
    ).value!
    event_store.read(
      streams.resource_lease(resource.resource_key_hash),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [
          "ResourceLeaseAcquired",
          "ResourceLeaseRenewed",
          "ResourceLeaseReleased",
          "ResourceLeaseExpired"
        ],
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def work_item_arguments(agent_id:, work_item_id:, change_set_id:, command_id:)
    {
      command_id:,
      actor: { kind: "agent", id: agent_id },
      change_set_id:,
      work_item_id:,
      repository_id: "billing",
      goal: "Implement #{work_item_id}",
      acceptance_criteria: [ "The work is verifiable" ]
    }
  end

  def assert_no_current_coordination_facts
    assert_acceptance_equal([], command_events(@current_arguments.fetch(:command_id)), "Command facts")
    assert_acceptance_equal([], change_set_events(@current_arguments.fetch(:change_set_id)), "ChangeSet facts")
    return unless @current_arguments[:work_item_id]

    assert_acceptance_equal([], work_item_events(@current_arguments.fetch(:work_item_id)), "WorkItem facts")
  end

  def assert_acceptance(condition, message)
    raise message unless condition
  end

  def assert_acceptance_equal(expected, actual, context)
    return if expected == actual

    raise "#{context}: expected #{expected.inspect}, got #{actual.inspect}"
  end

  private

  def mcp_session
    @mcp_session ||= ActionDispatch::Integration::Session.new(Rails.application).tap do |session|
      session.host! "localhost"
    end
  end

  def next_request_id
    @request_id = @request_id.to_i + 1
  end

  def modern_params(params)
    extensions = tasks_capable? ? { TASKS_EXTENSION => {} } : {}
    params.merge(
      _meta: {
        "io.modelcontextprotocol/protocolVersion": PROTOCOL_VERSION,
        "io.modelcontextprotocol/clientCapabilities": { extensions: },
        "io.modelcontextprotocol/clientInfo": { name: "cucumber", version: "1.0" }
      }
    )
  end

  def request_headers(method:, name:)
    {
      "Content-Type" => "application/json",
      "Accept" => "application/json, text/event-stream",
      "MCP-Protocol-Version" => PROTOCOL_VERSION,
      "Mcp-Method" => method,
      "Mcp-Name" => name
    }.compact
  end

  def event_store
    @event_store ||= Coordinator::Write::EventStore.new(client: PgEventstore.client)
  end

  def streams
    @streams ||= Coordinator::Write::StreamFactory.new
  end
end

World(McpAcceptanceWorld)
