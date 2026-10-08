# frozen_string_literal: true

module AdvisoryWorkIntentionAcceptanceWorld
  ADVISORY_CHANGE_SET_ID = "CS-CUC-ADVISORY-INTENTIONS"
  ADVISORY_BASE_COMMIT_OID = "a" * 40

  def prepare_advisory_work_intention_agents
    prepare_mcp_clients("agent-a", "agent-b")
    @advisory_agents = {
      "A" => {
        agent_id: "agent-a",
        client_id: "agent-a",
        work_item_id: "W-CUC-ADVISORY-A",
        attempt_id: "A-CUC-ADVISORY-A"
      },
      "B" => {
        agent_id: "agent-b",
        client_id: "agent-b",
        work_item_id: "W-CUC-ADVISORY-B",
        attempt_id: "A-CUC-ADVISORY-B"
      }
    }

    submit_and_execute(
      "change_set_create",
      command_id: "cuc-advisory-change-set-create",
      actor: { kind: "agent", id: "planner" },
      change_set_id: ADVISORY_CHANGE_SET_ID,
      goal: "Coordinate compatible and incompatible parallel work",
      acceptance_criteria: [
        "Shared intentions may overlap",
        "Any overlap involving an exclusive intention is rejected"
      ]
    )
    @advisory_agents.each_value do |agent|
      submit_and_execute(
        "work_item_create",
        command_id: "cuc-advisory-work-item-create-#{agent.fetch(:agent_id)}",
        actor: { kind: "agent", id: "planner" },
        change_set_id: ADVISORY_CHANGE_SET_ID,
        work_item_id: agent.fetch(:work_item_id),
        repository_id: acceptance_repository_id,
        goal: "Implement #{agent.fetch(:work_item_id)}",
        acceptance_criteria: [ "Work intentions remain attributable" ]
      )
    end
    submit_and_execute(
      "change_set_activate",
      command_id: "cuc-advisory-change-set-activate",
      actor: { kind: "agent", id: "planner" },
      change_set_id: ADVISORY_CHANGE_SET_ID
    )
    @advisory_agents.each_value { await_work_item_ready(_1.fetch(:work_item_id)) }
    @advisory_agents.each_value do |agent|
      submit_and_execute(
        "work_item_acquire",
        client_id: agent.fetch(:client_id),
        command_id: "cuc-advisory-work-item-acquire-#{agent.fetch(:agent_id)}",
        actor: { kind: "agent", id: agent.fetch(:agent_id) },
        change_set_id: ADVISORY_CHANGE_SET_ID,
        work_item_id: agent.fetch(:work_item_id),
        attempt_id: agent.fetch(:attempt_id),
        base_snapshots: [
          { repository_id: acceptance_repository_id, commit_oid: ADVISORY_BASE_COMMIT_OID }
        ]
      )
    end
  end

  def advisory_agent(name)
    @advisory_agents.fetch(name)
  end

  def prepare_exhausted_advisory_boundary
    agent = advisory_agent("A")
    @advisory_capacity_resources = 31.times.map do |index|
      advisory_resource("file", "capacity/item-#{index}.rb", agent:)
    end
    task_id = submit_and_execute(
      "work_intention_set_declare", client_id: agent.fetch(:client_id),
      command_id: "cuc-capacity-owner", actor: { kind: "agent", id: agent.fetch(:agent_id) },
      change_set_id: ADVISORY_CHANGE_SET_ID, work_item_id: agent.fetch(:work_item_id),
      attempt_id: agent.fetch(:attempt_id), repository_id: acceptance_repository_id,
      base_commit_oid: ADVISORY_BASE_COMMIT_OID, ttl_seconds: 300,
      resources: @advisory_capacity_resources.map do |resource|
        { resource_id: resource.fetch(:resource_id), purpose: "Ongoing compatible work" }
      end
    )
    result = task_request("tasks/get", task_id, client_id: agent.fetch(:client_id))
    receipt = result.dig("result", "result", "structuredContent", "data")
    assert_acceptance_equal(false, result.dig("result", "result", "isError"), "Capacity owner declaration")
    # Every historical renewal also crosses public MCP. No raw event insertion,
    # internal command invocation, overridden clock or failure collaborator is used.
    renewals = Coordinator::Write::EventQueries::WORK_INTENTION_BOUNDARY_MAXIMUM_COUNT / 31
    renewals.times do |index|
      task_id = submit_and_execute(
        "work_intention_set_renew", client_id: agent.fetch(:client_id),
        task_timeout_seconds: LiveSubscriptions::HIGH_VOLUME_TIMEOUT_SECONDS,
        command_id: "cuc-capacity-renew-#{index}", actor: { kind: "agent", id: agent.fetch(:agent_id) },
        change_set_id: ADVISORY_CHANGE_SET_ID, work_item_id: agent.fetch(:work_item_id),
        attempt_id: agent.fetch(:attempt_id), intention_set_id: receipt.fetch("intention_set_id"),
        intentions: receipt.fetch("intentions").map { _1.slice("resource_id", "intention_id", "fencing_token") },
        ttl_seconds: 301 + index
      )
      renewed = task_request("tasks/get", task_id, client_id: agent.fetch(:client_id))
      assert_acceptance_equal(false, renewed.dig("result", "result", "isError"), "Capacity renewal #{index}")
      renewal_data = renewed.dig("result", "result", "structuredContent", "data")
      assert_acceptance_equal(31, renewal_data.fetch("intention_count"), "Capacity renewal membership")
      assert_acceptance(
        renewal_data.fetch("expires_at") > renewal_data.fetch("previous_expires_at"),
        "Each capacity renewal must extend the deadline and record lifecycle facts"
      )
    end
  end

  def submit_exhausted_advisory_request(operation)
    agent = advisory_agent("B")
    @advisory_capacity_operation = operation
    arguments = {
      command_id: "cuc-capacity-#{operation}", actor: { kind: "agent", id: agent.fetch(:agent_id) },
      change_set_id: ADVISORY_CHANGE_SET_ID, work_item_id: agent.fetch(:work_item_id),
      attempt_id: agent.fetch(:attempt_id), repository_id: acceptance_repository_id,
      base_commit_oid: ADVISORY_BASE_COMMIT_OID,
      resources: @advisory_capacity_resources.map { { resource_id: _1.fetch(:resource_id) } }
    }
    if operation == "expansion"
      unrelated = advisory_resource("file", "unrelated/existing.rb", agent:)
      @advisory_capacity_existing = declare_advisory_intention(
        agent:, resource: unrelated, mode: "shared", command_id: "cuc-capacity-requester-existing"
      )
      arguments[:intention_set_id] = @advisory_capacity_existing.dig(:outcome, "data", "intention_set_id")
    else
      arguments[:ttl_seconds] = 300
    end
    tool = operation == "expansion" ? "work_intention_set_expand" : "work_intention_set_declare"
    response = call_tool(tool, arguments, client_id: agent.fetch(:client_id))
    task_id = response.dig("result", "taskId")
    assert_acceptance(task_id, "History-budget request did not allocate a Task: #{response.inspect}")
    start_process_subscriptions
    @advisory_capacity_task = await_task_terminal(
      task_id, client_id: agent.fetch(:client_id), timeout_seconds: LiveSubscriptions::HIGH_VOLUME_TIMEOUT_SECONDS
    )
  end

  def advisory_resource(kind, path, agent:)
    {
      kind:,
      path:,
      resource_id: resolve_resource_id(
        kind:,
        path:,
        client_id: agent.fetch(:client_id),
        actor_id: agent.fetch(:agent_id)
      )
    }
  end

  def advisory_declaration_arguments(agent:, resource:, mode:, command_id:, ttl_seconds: 300, purpose: nil, context: nil)
    {
      command_id:,
      actor: { kind: "agent", id: agent.fetch(:agent_id) },
      change_set_id: ADVISORY_CHANGE_SET_ID,
      work_item_id: agent.fetch(:work_item_id),
      attempt_id: agent.fetch(:attempt_id),
      repository_id: acceptance_repository_id,
      base_commit_oid: ADVISORY_BASE_COMMIT_OID,
      resources: [
        {
          resource_id: resource.fetch(:resource_id),
          mode:,
          purpose: purpose || "#{agent.fetch(:agent_id)} plans #{mode} work on #{resource.fetch(:path)}",
          context: context || "#{agent.fetch(:attempt_id)} is coordinating this edit"
        }
      ],
      ttl_seconds:
    }
  end

  def submit_advisory_declaration(agent:, resource:, mode:, command_id:, ttl_seconds: 300, purpose: nil, context: nil)
    arguments = advisory_declaration_arguments(
      agent:,
      resource:,
      mode:,
      command_id:,
      ttl_seconds:,
      purpose:,
      context:
    )
    response = call_tool(
      "work_intention_set_declare",
      arguments,
      client_id: agent.fetch(:client_id)
    )
    task_id = response.dig("result", "taskId")
    assert_acceptance(task_id, "work_intention_set_declare did not return a Task: #{response.inspect}")
    { agent:, resource:, mode:, command_id:, arguments:, task_id: }
  end

  def await_advisory_declaration(declaration)
    state = await_task_terminal(
      declaration.fetch(:task_id),
      client_id: declaration.dig(:agent, :client_id)
    )
    declaration.merge(
      state:,
      outcome: state.dig("result", "result", "structuredContent")
    )
  end

  def declare_advisory_intention(**arguments)
    declaration = submit_advisory_declaration(**arguments)
    start_process_subscriptions
    await_advisory_declaration(declaration)
  end

  def advisory_intention_reference(declaration)
    declaration.dig(:outcome, "data", "intentions").sole
  end

  def withdraw_advisory_intention(declaration, command_id:)
    data = declaration.dig(:outcome, "data")
    task_id = submit_and_execute(
      "work_intention_set_withdraw",
      client_id: declaration.dig(:agent, :client_id),
      command_id:,
      actor: { kind: "agent", id: declaration.dig(:agent, :agent_id) },
      change_set_id: ADVISORY_CHANGE_SET_ID,
      work_item_id: declaration.dig(:agent, :work_item_id),
      attempt_id: declaration.dig(:agent, :attempt_id),
      intention_set_id: data.fetch("intention_set_id"),
      intentions: data.fetch("intentions").map do |intention|
        intention.slice("resource_id", "intention_id", "fencing_token")
      end
    )
    state = task_request(
      "tasks/get",
      task_id,
      client_id: declaration.dig(:agent, :client_id)
    )
    assert_acceptance_equal("completed", state.dig("result", "status"), "Withdrawal Task status")
    assert_acceptance_equal(false, state.dig("result", "result", "isError"), "Withdrawal Task result")
  end
end

World(AdvisoryWorkIntentionAcceptanceWorld)
