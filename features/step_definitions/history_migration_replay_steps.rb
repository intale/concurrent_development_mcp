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
  eventually("bounded history migration to complete", timeout_seconds: LiveSubscriptions::HIGH_VOLUME_TIMEOUT_SECONDS) do
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
    restored = items.one? && items.first
    complete = restored && restored.fetch("display_name") == @repository_arguments.fetch(:display_name) &&
               restored.fetch("paths") == @repository_arguments.fetch(:paths)
    [ complete, restored ]
  end
  @history_target_repository_id = result.fetch("repository_id")
  assert_acceptance(@history_target_repository_id != @history_repository_id, "Restored identity must be newly allocated")
  assert_acceptance_equal(@repository_arguments.fetch(:display_name), result.fetch("display_name"), "Restored name")
  assert_acceptance_equal(@repository_arguments.fetch(:paths), result.fetch("paths"), "Restored attributed path")
end

Then("the restored receipt refers to facts owned by its original logical command") do
  receipt = eventually("restored command receipt") do
    result = call_tool("operation_get", { command_id: @repository_arguments.fetch(:command_id) }).dig("result", "structuredContent")
    [ result && result.fetch("status") == "ok", result ]
  end
  events = receipt.dig("data", "emitted_events")
  assert_acceptance(events.any? { _1.fetch("type") == "RepositoryRegistered" }, "Restored command must expose registration")
  assert_acceptance_equal(@history_target_repository_id, receipt.dig("data", "result", "repository_id"), "Restored receipt repository")
end

Then("the migration does not copy its own maintenance facts into restored history") do
  restored = PgEventstore.client(:migration_target).read(
    PgEventstore::Stream.all_stream,
    options: {
      max_count: 1,
      filter: { event_types: %w[HistoryMigrationStarted HistoryMigrationPageCreated HistoryMigrationCompleted] }
    }
  )
  assert_acceptance(restored.empty?, "Restored domain history must not contain migration-control facts")
end
