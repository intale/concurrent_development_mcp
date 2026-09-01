# frozen_string_literal: true

COORDINATION_WORK_ITEMS_QUERY = <<~GRAPHQL.freeze
  query CoordinationWorkItems($projectRef: ID!) {
    projectWorkItems(projectRef: $projectRef, first: 100) {
      nodes { id domainStatus presentationStatus activeAgentId activeAttemptId attemptStatus }
    }
  }
GRAPHQL

COORDINATION_DEPENDENCIES_QUERY = <<~GRAPHQL.freeze
  query CoordinationDependencies($projectRef: ID!) {
    projectDependencies(projectRef: $projectRef, first: 100) {
      nodes { id producerWorkItemId consumerWorkItemId blocking }
    }
  }
GRAPHQL

COORDINATION_WORK_ITEM_DETAIL_QUERY = <<~GRAPHQL.freeze
  query CoordinationWorkItemDetail($projectRef: ID!, $workItemId: ID!) {
    projectWorkItem(projectRef: $projectRef, workItemId: $workItemId) {
      workItem { id presentationStatus activeAgentId }
      attempt { id agentId status }
      checkpoint { id checkpointKind }
    }
  }
GRAPHQL

Given("projected dashboard rows contain pending, ready, and running scheduled work") do
  create_dashboard_project
  create_dashboard_context("planning", [ dashboard_work_item_row("W-pending", "planned") ])
  create_dashboard_context(
    "active",
    [
      dashboard_work_item_row("W-ready", "ready"),
      dashboard_work_item_row("W-running", "acquired", attempt_id: "A-running")
    ]
  )
  create_dashboard_attempt("active", "W-running", "A-running", "luna-running")
end

Given(
  "projected dashboard rows contain agents {string} and {string} on distinct running work"
) do |first_agent, second_agent|
  create_dashboard_project
  create_dashboard_context(
    "concurrent",
    [
      dashboard_work_item_row("W-luna-one", "acquired", attempt_id: "A-luna-one"),
      dashboard_work_item_row("W-luna-two", "acquired", attempt_id: "A-luna-two")
    ]
  )
  create_dashboard_attempt("concurrent", "W-luna-one", "A-luna-one", first_agent)
  create_dashboard_attempt("concurrent", "W-luna-two", "A-luna-two", second_agent)
end

Given("projected dashboard rows contain a running WorkItem with a Candidate checkpoint") do
  create_dashboard_project
  create_dashboard_context(
    "detail",
    [ dashboard_work_item_row("W-detail", "acquired", attempt_id: "A-detail") ]
  )
  create_dashboard_attempt("detail", "W-detail", "A-detail", "luna-detail")
  FactoryBot.create(
    :coordinator_read_candidate,
    candidate_id: "CAND-detail",
    change_set_id: @coordination_dashboard_change_sets.fetch("detail"),
    work_item_id: "W-detail",
    attempt_id: "A-detail",
    agent_id: "luna-detail",
    repository_id: @coordination_dashboard_repository_id,
    checkpoint_kind: "intermediate"
  )
end

Given("projected dashboard rows contain an unmet work-item dependency") do
  create_dashboard_project
  create_dashboard_context(
    "blocked",
    [
      dashboard_work_item_row("W-producer", "ready"),
      dashboard_work_item_row("W-consumer", "planned")
    ],
    dependencies: [
      {
        "dependency_id" => "D-producer-consumer",
        "producer_work_item_id" => "W-producer",
        "consumer_work_item_id" => "W-consumer",
        "dependency_kind" => "requires_completion",
        "required_output" => nil,
        "source_event" => nil,
        "declared_at" => "2026-08-31T12:00:00.000000Z",
        "satisfied_at" => nil
      }
    ]
  )
end

Given("projected dashboard rows contain scheduled work for the selected and an unrelated project") do
  create_dashboard_project
  selected_repository_id = @coordination_dashboard_repository_id
  selected_project_ref = @coordination_dashboard_project_ref
  create_dashboard_context(
    "isolation-selected",
    [ dashboard_work_item_row("W-selected", "ready", change_set_key: "isolation-selected") ]
  )

  create_dashboard_project
  create_dashboard_context(
    "isolation-unrelated",
    [ dashboard_work_item_row("W-unrelated", "ready", change_set_key: "isolation-unrelated") ]
  )
  @coordination_dashboard_repository_id = selected_repository_id
  @coordination_dashboard_project_ref = selected_project_ref
end

Given("a dashboard work item is ready in the latest projected rows") do
  create_dashboard_project
  @stale_dashboard_context = create_dashboard_context(
    "stale",
    [ dashboard_work_item_row("W-stale", "ready") ]
  )
end

When("the browser queries the projected coordination dashboard") do
  @coordination_dashboard_payload = query_coordination_dashboard
end

When("the browser opens the projected WorkItem detail") do
  @coordination_work_item_detail_payload = coordination_graphql_query(
    COORDINATION_WORK_ITEM_DETAIL_QUERY,
    projectRef: @coordination_dashboard_project_ref,
    workItemId: "W-detail"
  )
end

When("a newer acquisition has not reached the projected rows") do
  @coordination_dashboard_stale_payload = query_coordination_dashboard
end

When("the projected dashboard rows catch up") do
  document = @stale_dashboard_context.document.deep_dup
  document["work_items"] = [ dashboard_work_item_row("W-stale", "acquired", attempt_id: "A-stale") ]
  document["attempts"] = []
  @stale_dashboard_context.update!(document:, last_processed_at: Time.utc(2026, 8, 31, 12, 5))
  create_dashboard_attempt("stale", "W-stale", "A-stale", "luna-stale")
  @coordination_dashboard_payload = query_coordination_dashboard
end

Then("the dashboard presents the exact scheduled work states") do
  statuses = dashboard_work_items(coordination_dashboard_data(@coordination_dashboard_payload)).to_h do |item|
    [ item.fetch("id"), [ item.fetch("domainStatus"), item.fetch("presentationStatus") ] ]
  end
  assert_acceptance_equal(
    {
      "W-pending" => [ "planned", "PENDING" ],
      "W-ready" => [ "ready", "READY" ],
      "W-running" => [ "acquired", "RUNNING" ]
    },
    statuses,
    "Scheduled WorkItem states"
  )
end

Then("both running agents retain their distinct Attempt attribution") do
  items = dashboard_work_items(coordination_dashboard_data(@coordination_dashboard_payload))
  attribution = items.to_h do |item|
    [ item.fetch("id"), [ item.fetch("activeAgentId"), item.fetch("activeAttemptId"), item.fetch("attemptStatus") ] ]
  end
  assert_acceptance_equal(
    {
      "W-luna-one" => [ "luna-one", "A-luna-one", "started" ],
      "W-luna-two" => [ "luna-two", "A-luna-two", "started" ]
    },
    attribution,
    "Concurrent agent attribution"
  )
end

Then("the WorkItem detail presents its exact Attempt and checkpoint attribution") do
  detail = graphql_data(@coordination_work_item_detail_payload).fetch("projectWorkItem")
  assert_acceptance_equal(
    [ "W-detail", "RUNNING", "luna-detail" ],
    detail.fetch("workItem").values_at("id", "presentationStatus", "activeAgentId"),
    "Focused WorkItem"
  )
  assert_acceptance_equal(
    [ "A-detail", "luna-detail", "started" ],
    detail.fetch("attempt").values_at("id", "agentId", "status"),
    "Focused Attempt"
  )
  assert_acceptance_equal(
    [ "CAND-detail", "intermediate" ],
    detail.fetch("checkpoint").values_at("id", "checkpointKind"),
    "Focused checkpoint"
  )
end

Then("the dashboard identifies the blocking producer and consumer") do
  dependency = coordination_dashboard_data(@coordination_dashboard_payload)
    .fetch("dependencies").fetch("nodes").sole
  assert_acceptance_equal(
    {
      "id" => "D-producer-consumer",
      "producerWorkItemId" => "W-producer",
      "consumerWorkItemId" => "W-consumer",
      "blocking" => true
    },
    dependency,
    "Dependency blocker"
  )
end

Then("only the selected project's scheduled work is presented") do
  ids = dashboard_work_items(coordination_dashboard_data(@coordination_dashboard_payload)).map do |item|
    item.fetch("id")
  end
  assert_acceptance_equal([ "W-selected" ], ids, "Project-isolated scheduled work")
end

Then("the dashboard remains available with the ready state") do
  item = dashboard_work_item(coordination_dashboard_data(@coordination_dashboard_stale_payload), "W-stale")
  assert_acceptance_equal("READY", item&.fetch("presentationStatus"), "Available stale dashboard state")
end

Then("the dashboard presents the work item as running") do
  item = dashboard_work_item(coordination_dashboard_data(@coordination_dashboard_payload), "W-stale")
  assert_acceptance_equal(
    [ "RUNNING", "luna-stale", "A-stale" ],
    [ item.fetch("presentationStatus"), item.fetch("activeAgentId"), item.fetch("activeAttemptId") ],
    "Advanced dashboard state"
  )
end

def create_dashboard_project
  @coordination_dashboard_repository_id = SecureRandom.uuid_v7
  scope = "project:test/dashboard-#{@coordination_dashboard_repository_id}"
  FactoryBot.create(
    :coordinator_read_repository,
    repository_id: @coordination_dashboard_repository_id,
    repository_key: "dashboard-#{@coordination_dashboard_repository_id}",
    scope:,
    display_name: "Coordination dashboard"
  )
  @coordination_dashboard_project_ref = Coordinator::Read::Web::ProjectReference.new.encode(scope:)
  @coordination_dashboard_change_sets = {}
end

def create_dashboard_context(key, work_items, dependencies: [])
  change_set_id = "CS-#{key}"
  @coordination_dashboard_change_sets[key] = change_set_id
  template = FactoryBot.build(
    :coordinator_read_coord_context,
    change_set_id:,
    repository_id: @coordination_dashboard_repository_id,
    work_item_id: work_items.first.fetch("work_item_id")
  )
  document = template.document.deep_dup
  document["change_set"]["status"] = key == "planning" ? "planning" : "active"
  document["work_items"] = work_items
  document["work_item_ids"] = work_items.map { _1.fetch("work_item_id") }
  document["dependencies"] = dependencies
  document["attempts"] = []
  FactoryBot.create(
    :coordinator_read_coord_context,
    change_set_id:,
    repository_id: @coordination_dashboard_repository_id,
    document:
  )
end

def create_dashboard_attempt(change_set_key, work_item_id, attempt_id, agent_id)
  FactoryBot.create(
    :coordinator_read_attempt_history,
    attempt_id:,
    change_set_id: @coordination_dashboard_change_sets.fetch(change_set_key),
    work_item_id:,
    agent_id:,
    status: "started",
    started_at_domain: Time.utc(2026, 8, 31, 12, 4)
  )
end

def dashboard_work_item_row(work_item_id, status, attempt_id: nil, change_set_key: nil)
  timestamp = "2026-08-31T12:00:00.000000Z"
  {
    "work_item_id" => work_item_id,
    "change_set_id" => "CS-#{change_set_key || dashboard_change_set_key(work_item_id)}",
    "repository_id" => @coordination_dashboard_repository_id,
    "goal" => "Coordinate #{work_item_id}",
    "acceptance_criteria" => [ "The dashboard presents #{work_item_id}" ],
    "competitive_mode" => false,
    "status" => status,
    "active_attempt_id" => attempt_id,
    "active_agent_id" => attempt_id && "embedded-agent",
    "selected_candidate_id" => nil,
    "selected_candidate_event" => nil,
    "produced_outputs" => [],
    "created_at" => timestamp,
    "made_ready_at" => status == "planned" ? nil : timestamp,
    "acquired_at" => attempt_id && timestamp,
    "selected_at" => nil,
    "completed_at" => status == "completed" ? timestamp : nil
  }
end

def dashboard_change_set_key(work_item_id)
  return "planning" if work_item_id == "W-pending"
  return "active" if %w[W-ready W-running].include?(work_item_id)
  return "concurrent" if work_item_id.start_with?("W-luna")
  return "detail" if work_item_id == "W-detail"
  return "blocked" if %w[W-producer W-consumer].include?(work_item_id)

  "stale"
end

def query_coordination_dashboard
  work_items = coordination_graphql_query(
    COORDINATION_WORK_ITEMS_QUERY,
    projectRef: @coordination_dashboard_project_ref
  )
  dependencies = coordination_graphql_query(
    COORDINATION_DEPENDENCIES_QUERY,
    projectRef: @coordination_dashboard_project_ref
  )
  {
    "data" => {
      "coordination" => {
        "workItems" => graphql_data(work_items).fetch("projectWorkItems"),
        "dependencies" => graphql_data(dependencies).fetch("projectDependencies")
      }
    }
  }
end

def coordination_graphql_query(query, variables)
  @coordination_dashboard_graphql_session ||= ActionDispatch::Integration::Session.new(Rails.application).tap do |session|
    session.host! "localhost"
  end
  @coordination_dashboard_graphql_session.post(
    "/graphql",
    params: { query:, variables: },
    as: :json
  )
  response = @coordination_dashboard_graphql_session.response
  assert_acceptance(response.status == 200, "Dashboard GraphQL returned HTTP #{response.status}: #{response.body}")
  JSON.parse(response.body)
end

def coordination_dashboard_data(payload)
  errors = payload.fetch("errors", [])
  assert_acceptance(errors.empty?, "Dashboard GraphQL failed: #{errors.inspect}")
  payload.dig("data", "coordination")
end

def graphql_data(payload)
  errors = payload.fetch("errors", [])
  assert_acceptance(errors.empty?, "Focused coordination GraphQL failed: #{errors.inspect}")
  payload.fetch("data")
end

def dashboard_work_items(dashboard)
  dashboard.fetch("workItems").fetch("nodes")
end

def dashboard_work_item(dashboard, work_item_id)
  dashboard_work_items(dashboard).find { _1.fetch("id") == work_item_id }
end
