# frozen_string_literal: true

Then("no history-transfer tool or instruction is advertised") do
  names = @migration_tools.map { _1.fetch("name") }
  retained_imports = %w[
    skill_publish skill_publish_batch development_artifact_capture
    development_artifact_capture_batch development_artifact_update
    development_artifact_relation_declare development_artifact_relation_declare_batch
  ]
  assert_acceptance((retained_imports - names).empty?, "Product import tools are available")
  assert_acceptance(!names.include?("history_migration_start"), "Retired transfer tool is absent")
  instructions = @migration_discovery.dig("result", "instructions")
  assert_acceptance(!instructions.include?("history_migration_start"), "Retired transfer instructions are absent")
end

When("the agent requests the retired database-transfer tool") do
  @retired_transfer_actor = { kind: "agent", id: "migration-retirement-agent" }
  @retired_transfer_request = "cmd-cuc-retired-history-transfer"
  @retired_transfer_response = call_tool(
    "history_migration_start",
    { command_id: @retired_transfer_request, actor: @retired_transfer_actor },
    expected_status: 400
  )
end

Then("the request is rejected before a command or Task is recorded") do
  assert_acceptance_equal(-32_602, @retired_transfer_response.dig("error", "code"), "Retired tool protocol error")
  assert_acceptance(!@retired_transfer_response.dig("result", "taskId"), "Retired tool admitted a Task")
  facts = task_events_for_request(@retired_transfer_request, actor: @retired_transfer_actor)
  assert_acceptance(facts.empty?, "Retired tool persisted Task admission")
  marker = Coordinator::Write::CommandLifecycle::RequestMarker.new.call(
    actor: Coordinator::Write::Commands::Actor.new(**@retired_transfer_actor),
    request_id: @retired_transfer_request
  )
  registrations = event_store.read_global_marked(
    Coordinator::Write::GlobalMarkedEventReadCriteria.new(
      stream_context: "CoordinatorControl",
      stream_name: "Command",
      event_types: [ "CommandRegistered" ],
      markers: [ marker ],
      maximum_count: 1,
      direction: :asc
    )
  )
  assert_acceptance(registrations.empty?, "Retired tool persisted Command admission")
end
