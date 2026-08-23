# frozen_string_literal: true

module AgentChoiceScenario
  module_function

  def record_no_policy_choice(prefix:, repository_id: "billing", actor_id: "agent-a")
    identifiers = identifiers(prefix)
    context = context(identifiers:, repository_id:)
    seed_active_attempt(identifiers:, repository_id:, actor_id:)
    decision_context = resolve_context(context)

    execute(Coordinator::Write::Operations::ExecuteRecordAgentChoice, {
      command_id: "cmd-#{prefix}-choice",
      actor: { kind: "agent", id: actor_id },
      choice_id: identifiers.fetch(:choice_id),
      choice_type: "testing.framework",
      selected: { option_id: "rspec", summary: "RSpec" },
      alternatives: [ { option_id: "minitest", summary: "Minitest" } ],
      reason_summary: "Use the testing framework that fits the current coordination policy.",
      context:,
      decision_context: decision_context.to_h
    })

    {
      identifiers:,
      context:,
      decision_context:,
      events: event_store.read(
        streams.agent_choice(identifiers.fetch(:choice_id)),
        Coordinator::Write::EventQueries::AGENT_CHOICE_EXISTENCE
      )
    }
  end

  def identifiers(prefix)
    {
      change_set_id: "CS-#{prefix}",
      work_item_id: "W-#{prefix}",
      attempt_id: "A-#{prefix}",
      choice_id: "CHO-#{prefix}"
    }
  end

  def context(identifiers:, repository_id:)
    {
      workspace_id: nil,
      repository_id:,
      change_set_id: identifiers.fetch(:change_set_id),
      work_item_id: identifiers.fetch(:work_item_id),
      attempt_id: identifiers.fetch(:attempt_id),
      phase: "implementation",
      language: "ruby",
      paths: [ "spec/models/order_spec.rb" ],
      environment: "test",
      agent_role: "implementer"
    }
  end

  def seed_active_attempt(identifiers:, repository_id:, actor_id:)
    execute(Coordinator::Write::Operations::ExecuteCreateChangeSet, {
      command_id: "seed-#{identifiers.fetch(:change_set_id)}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: identifiers.fetch(:change_set_id),
      goal: "Record an AgentChoice",
      acceptance_criteria: [ "The choice is projected" ]
    })
    execute(Coordinator::Write::Operations::ExecuteCreateWorkItem, {
      command_id: "seed-#{identifiers.fetch(:work_item_id)}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: identifiers.fetch(:change_set_id),
      work_item_id: identifiers.fetch(:work_item_id),
      repository_id:,
      goal: "Choose a testing framework",
      acceptance_criteria: [ "The selected framework is recorded" ]
    })
    execute(Coordinator::Write::Operations::ExecuteActivateChangeSet, {
      command_id: "seed-activate-#{identifiers.fetch(:change_set_id)}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: identifiers.fetch(:change_set_id)
    })
    activation = event_store.read(
      streams.change_set(identifiers.fetch(:change_set_id)),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACQUISITION
    ).find { _1.type == "ChangeSetActivated" }
    Coordinator::Processes::ProcessManagers::ChangeSetReadiness.new(event_store:).call(activation)
    execute(Coordinator::Write::Operations::ExecuteAcquireWorkItem, {
      command_id: "seed-#{identifiers.fetch(:attempt_id)}",
      actor: { kind: "agent", id: actor_id },
      change_set_id: identifiers.fetch(:change_set_id),
      work_item_id: identifiers.fetch(:work_item_id),
      attempt_id: identifiers.fetch(:attempt_id),
      base_snapshots: [ { repository_id:, commit_oid: "a" * 40 } ]
    })
  end

  def resolve_context(context)
    result = Coordinator::Read::Queries::DecisionResolve.new.call(
      topic_id: "testing.framework",
      context:
    ).value!
    result.data.decision_context
  end

  def execute(operation_class, input)
    operation_class.new(event_store:).call(input).value!
  end

  def event_store
    Coordinator::Write::EventStore.new(client: PgEventstore.client)
  end

  def streams
    Coordinator::Write::StreamFactory.new
  end
end
