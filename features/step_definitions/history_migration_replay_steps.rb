# frozen_string_literal: true

Given("frozen historical repository and Task evidence exists") do
  step('the agent registers a caller-created Repository for scope "project:history-replay"')
  @history_repository_id = @repository_id
end

When("the agent starts a history migration through MCP") do
  task = submit_and_execute(
    "history_migration_start", command_id: "history-replay-start", actor: { kind: "agent", id: "history-agent" },
    page_size: 1000
  )
  result = task_request("tasks/get", task).dig("result", "result")
  assert_acceptance_equal(false, result.fetch("isError"), "Migration admission")
  @history_migration_id = result.dig("structuredContent", "data", "migration_id")
  eventually("bounded history migration to complete") do
    event = event_store.read_latest(
      streams.history_migration(@history_migration_id),
      Coordinator::Write::LatestEventReadCriteria.new(event_types: [ "HistoryMigrationCompleted" ])
    )
    [ !event.nil?, event&.type ]
  end
end

When("the migrated repository and command receipts are replayed") do
  stop_live_subscriptions
  ReadModelTestSafety.clean!
  start_history_replay_subscriptions
end

Then("the agent discovers the restored repository through MCP") do
  result = eventually("restored repository discovery") do
    result = call_tool("repository_list", { scope: "project:history-replay", limit: 20 }).dig("result", "structuredContent")
    items = result.dig("data", "page", "items") || []
    [ items.one?, items.first ]
  end
  @history_target_repository_id = result.fetch("repository_id")
  assert_acceptance(@history_target_repository_id != @history_repository_id, "Restored identity must be newly allocated")
  assert_acceptance_equal(@repository_arguments.fetch(:display_name), result.fetch("display_name"), "Restored name")
  assert_acceptance_equal(@repository_arguments.fetch(:paths), result.fetch("paths"), "Restored attributed path")
end

Then("the restored receipt refers to facts owned by its original logical command") do
  receipt = eventually("restored command receipt") do
    record = Coordinator::Read::CommandReceipt.find_by(tool_name: "repository_register")
    [ !record.nil?, record ]
  end
  target_store = Coordinator::Write::EventStore.new(client: PgEventstore.client(:migration_target))
  terminal = target_store.read_latest(
    Coordinator::Write::StreamFactory.new.command(receipt.command_id),
    Coordinator::Write::LatestEventReadCriteria.new(event_types: [ "CommandSucceeded" ])
  )
  events = target_store.read_command_events(
    Coordinator::Write::CommandEventReadCriteria.new(command_id: receipt.command_id, through_global_position: terminal.global_position, maximum_count: 10)
  )
  assert_acceptance(events.any? { _1.type == "RepositoryRegistered" }, "Restored command must own registration")
  assert_acceptance(events.all? { _1.metadata.fetch("command_id") == receipt.command_id }, "Restored command attribution")
  assert_acceptance_equal("ok", receipt.status, "Restored receipt status")
end
