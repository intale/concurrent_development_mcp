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
