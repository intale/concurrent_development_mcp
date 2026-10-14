# frozen_string_literal: true

When("the agent imports 1000 independent Skills through one MCP Batch") do
  @operation_batch_id = SecureRandom.uuid_v7
  items = 1000.times.map { |index| batch_skill_item(index:, name: "native-batch-skill-#{index}") }
  submit_skill_batch(items, wait_for_terminal: false)
end

Then("the maximum-sized Batch and all Skill projections converge without read-back confirmation loops") do
  # Test-harness synchronization, not an agent read-back or a service dependency.
  # Keep Read consumers stopped until the real Write Saga produces its backlog.
  eventually("maximum-sized import to commit its terminal fact", timeout_seconds: 600) do
    terminal = event_store.read_latest(streams.operation_batch(@operation_batch_id),
      Coordinator::Write::LatestEventReadCriteria.new(event_types: %w[OperationBatchCompleted OperationBatchCancelled]))
    [ !terminal.nil?, terminal&.type ]
  end
  task = await_task_terminal(@operation_batch_task_id, client_id: "import-agent", timeout_seconds: LiveSubscriptions::HIGH_VOLUME_TIMEOUT_SECONDS)
  assert_acceptance_equal(false, task.dig("result", "result", "isError"), "Whole Batch Task result")
  assert_acceptance_equal("succeeded", task.dig("result", "result", "structuredContent", "completion", "outcome"), "Batch settlement")
  await_read_model("maximum-sized Batch and latest Skill heads", timeout_seconds: LiveSubscriptions::HIGH_VOLUME_TIMEOUT_SECONDS) do
    batch = operation_batch_view(limit: 1)
    skills = Coordinator::Read::Skill.where(name: @submitted_operation_batch_items.map { _1.fetch("name") }).count
    [ batch && batch.fetch("succeeded") == 1000 && batch.fetch("pending").zero? && skills == 1000, { batch:, skill_count: skills } ]
  end
  manifest = operation_batch_manifest(limit: 100)
  assert_acceptance_equal(1000, manifest.fetch(:items).length, "All manifest items available in bounded pages")
  assert_acceptance(manifest.fetch(:pages).all? { _1.fetch("items").length <= 100 }, "Every Read page stays bounded")
  assert_acceptance_equal(1000, manifest.fetch(:items).map { _1.fetch("index") }.uniq.length, "Stable item identities")
end
