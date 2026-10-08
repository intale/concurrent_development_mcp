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

When("the agent records and updates an Artifact after the accepted history cutoff") do
  @history_base_id = @history_migration_id
  @history_base_events = PgEventstore.client(:migration_target).read(PgEventstore::Stream.all_stream, options: { max_count: 1000 }).map(&:id)
  @history_tail_after = Coordinator::Write::HistoryMigrations::SourceReader.new(client: PgEventstore.client).head_position
  captured = capture_artifact_task(
    command_id: "history-tail-capture", title: "Tail documentation", kind: "documentation",
    labels: [ "initial" ], locator: "mcp://history-tail/document", source_kind: "generated",
    content: { encoding: "utf-8", media_type: "text/markdown", text: "# Original" }, scope: "project:history-tail"
  )
  @history_tail_artifact_id = captured.dig("data", "artifact_id")
  @history_tail_observation_id = captured.dig("data", "observation_id")
  source = event_store.read_latest(streams.development_artifact(@history_tail_artifact_id), Coordinator::Write::LatestEventReadCriteria.new(
    event_types: %w[DevelopmentArtifactCreated DevelopmentArtifactLabelAdded DevelopmentArtifactContentChanged]
  ))
  result = update_artifact_task(
    command_id: "history-tail-update", artifact_id: @history_tail_artifact_id,
    expected_revision: source.stream_revision,
    changes: { content: { encoding: "utf-8", media_type: "text/markdown", text: "# Updated" }, labels: [ "updated" ] }
  )
  assert_acceptance_equal("ok", result.fetch("status"), "Tail update")
end

When("the agent cancels another Artifact capture before execution") do
  stop_process_subscriptions
  response = call_tool("development_artifact_capture", {
    command_id: "history-tail-cancelled", actor: { kind: "agent", id: "history-agent" },
    scope: "project:history-tail", title: "Cancelled documentation", kind: "documentation", labels: [],
    content: { encoding: "utf-8", media_type: "text/markdown", text: "Never captured" },
    source: { kind: "generated", locator: "mcp://history-tail/cancelled", revision: nil,
              observed_at: "2026-08-25T16:00:00.000000Z", collector: "cucumber/v1" }
  })
  @history_tail_cancelled_task_id = response.dig("result", "taskId")
  task_request("tasks/cancel", @history_tail_cancelled_task_id)
  assert_acceptance_equal("cancelled", task_request("tasks/get", @history_tail_cancelled_task_id).dig("result", "status"), "Source cancelled Task")
  start_process_subscriptions
end

When("the agent requests the closed development-memory suffix through MCP") do
  commands = PgEventstore.client.read(PgEventstore::Stream.all_stream, options: {
    max_count: 20, filter: { event_types: [ "CommandRegistered" ] }
  }).select { %w[history-tail-capture history-tail-update history-tail-cancelled].include?(_1.data.fetch("request_id")) }.map { _1.data.fetch("command_id") }.sort
  assert_acceptance_equal(3, commands.size, "Selected artifact command membership")
  reader = Coordinator::Write::HistoryMigrations::SourceReader.new(client: PgEventstore.client)
  upper = reader.head_position(source_command_ids: commands, source_after_position: @history_tail_after)
  task = submit_and_execute("history_migration_start",
    command_id: "history-tail-start", actor: { kind: "agent", id: "history-agent" }, page_size: 1000,
    source_after_position: @history_tail_after, source_upper_position: upper, source_command_ids: commands)
  result = task_request("tasks/get", task).dig("result", "result")
  assert_acceptance_equal(false, result.fetch("isError"), "Suffix admission")
  @history_migration_id = result.dig("structuredContent", "data", "migration_id")
  eventually("closed history suffix transfer", timeout_seconds: LiveSubscriptions::HIGH_VOLUME_TIMEOUT_SECONDS) do
    event = event_store.read_latest(streams.history_migration(@history_migration_id), Coordinator::Write::LatestEventReadCriteria.new(event_types: [ "HistoryMigrationCompleted" ]))
    [ !event.nil?, event&.type ]
  end
end

Then("the agent retrieves the current and original observed Artifact content through MCP") do
  artifact = eventually("restored suffix Artifact") do
    result = call_tool("development_artifact_list", { scope: "project:history-tail", limit: 10 }).dig("result", "structuredContent")
    items = result.dig("data", "page", "items") || []
    restored = items.one? && items.first
    [ restored && restored.fetch("labels") == [ "initial" ], restored && restored.slice("artifact_id", "observation_id", "labels") ]
  end
  current = eventually("restored current Artifact content") do
    content = call_tool("development_artifact_content_get", { artifact_id: artifact.fetch("artifact_id") }).dig("result", "structuredContent", "data", "content", "text")
    [ content == "# Updated", content ]
  end
  original = call_tool("development_artifact_content_get", { artifact_id: artifact.fetch("artifact_id"), observation_id: artifact.fetch("observation_id") }).dig("result", "structuredContent", "data", "content", "text")
  assert_acceptance_equal("# Updated", current, "Latest artifact content")
  assert_acceptance_equal("# Original", original, "Immutable observed content")
end

Then("the accepted base history is unchanged and maintenance history is excluded") do
  events = PgEventstore.client(:migration_target).read(PgEventstore::Stream.all_stream, options: { max_count: 1000 })
  assert_acceptance((@history_base_events - events.map(&:id)).empty?, "Base facts must remain unchanged")
  assert_acceptance_equal(1, events.count { _1.type == "RepositoryRegistered" }, "Base repository must not be duplicated")
  assert_acceptance(events.none? { _1.type.start_with?("HistoryMigration") || (_1.type == "ProcessStepPlanned" && _1.data.fetch("process_name").start_with?("history-migration")) }, "Maintenance history must be excluded")
  assert_acceptance(events.any? { _1.type == "DevelopmentArtifactObservationFactLinked" }, "Immutable observation references must be preserved")
  assert_acceptance(events.any? { _1.type == "DevelopmentArtifactLabelRemoved" && _1.data.fetch("label") == "initial" }, "Label removal facts must be preserved")
  assert_acceptance_equal(1, events.count { _1.type == "DevelopmentArtifactCreated" }, "Cancelled capture must not manufacture an Artifact")
end

Then("the cancelled capture retains terminal history without target work") do
  cancelled = PgEventstore.client(:migration_target).read(PgEventstore::Stream.all_stream, options: {
    max_count: 2, filter: { event_types: [ { type: "CoordinationTaskCancelled", markers: [ "history-migration:#{@history_migration_id}" ] } ] }
  }).sole
  task_id = cancelled.data.fetch("task_id")
  target_store = Coordinator::Write::EventStore.new(client: PgEventstore.client(:migration_target))
  loader = Coordinator::Write::Tasks::Loader.new(event_store: target_store)
  task = Coordinator::Write::Operations::GetCoordinationTask.new(loader:).call(task_id:).value!
  assert_acceptance(task_id != @history_tail_cancelled_task_id, "Restored Task identity must be newly allocated")
  assert_acceptance_equal("cancelled", task.status, "Restored cancellation status")
  assert_acceptance_equal("Cancelled before execution", task.status_message, "Restored cancellation reason")
end
