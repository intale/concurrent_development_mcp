# frozen_string_literal: true

PROJECT_RESOURCE_BROWSER_QUERY = <<~GRAPHQL.freeze
  query ProjectResourceBrowser($projectRef: ID!) {
    projectActiveResourceWorkIntentions(projectRef: $projectRef, first: 100) {
      nodes {
        id
        resourceId
        resourcePath
        agentId
        attemptId
        lastExpandedEventId
        lastRenewedEventId
      }
    }
  }
GRAPHQL
PROJECT_RESOURCE_WORK_INTENTION_DETAIL_QUERY = <<~GRAPHQL.freeze
  query ProjectResourceWorkIntentionDetail($projectRef: ID!, $intentionId: ID!) {
    projectResourceWorkIntention(projectRef: $projectRef, intentionId: $intentionId) {
      id
      agentId
      resourcePath
      status
      expiresAt
    }
  }
GRAPHQL

Given("projected resource rows contain two running agents but only one active work intention") do
  create_resource_browser_project
  leased = create_resource_browser_resource("app/models/owned.rb")
  create_resource_browser_attempt(
    "A-ui-owner",
    "luna-owner",
    resource: leased,
    trait: :with_work_intention_set
  )
  FactoryBot.create(
    :coordinator_read_attempt_history,
    attempt_id: "A-ui-blocked",
    change_set_id: "CS-ui-resources",
    work_item_id: "W-ui-blocked",
    agent_id: "luna-blocked",
    status: "started",
    base_snapshots: resource_browser_snapshots
  )
end

Given("projected resource rows represent expanded renewed withdrawn and expired work-intention lifecycles") do
  create_resource_browser_project
  first = create_resource_browser_resource("app/models/first.rb")
  second = create_resource_browser_resource("app/models/second.rb")
  released_first = create_resource_browser_resource("app/models/released_first.rb")
  released_second = create_resource_browser_resource("app/models/released_second.rb")
  expired = create_resource_browser_resource("app/models/expired.rb")

  create_resource_browser_attempt(
    "A-ui-lifecycle-active",
    "luna-active",
    resource: first,
    expanded_resource: second,
    trait: :expanded_and_renewed_work_intention_set
  )
  create_resource_browser_attempt(
    "A-ui-lifecycle-released",
    "luna-released",
    resource: released_first,
    expanded_resource: released_second,
    trait: :withdrawn_expanded_work_intention_set
  )
  @expired_resource_browser_intention_id = SecureRandom.uuid_v7
  create_resource_browser_attempt(
    "A-ui-lifecycle-expired",
    "luna-expired",
    resource: expired,
    trait: :with_work_intention_set,
    intention_id: @expired_resource_browser_intention_id,
    expires_at: Time.utc(2020, 8, 31, 12)
  )
end

Given("projected resource rows retain an old active work intention and one hundred one newer terminal Attempts") do
  create_resource_browser_project
  resource = create_resource_browser_resource("app/models/old_active.rb")
  create_resource_browser_attempt(
    "A-ui-old-active",
    "luna-old-active",
    resource:,
    trait: :with_work_intention_set
  )
  101.times do |index|
    FactoryBot.create(
      :coordinator_read_attempt_history,
      attempt_id: "A-ui-terminal-#{index}",
      change_set_id: "CS-ui-terminal-#{index}",
      work_item_id: "W-ui-terminal-#{index}",
      agent_id: "luna-terminal-#{index}",
      status: "completed",
      terminal_at_domain: Time.utc(2026, 8, 31, 12) + index.seconds,
      base_snapshots: resource_browser_snapshots
    )
  end
end

When("the browser queries the projected active Resource work intentions") do
  query_project_resource_work_intentions
end

When("the browser queries active work intentions and the expired intention detail") do
  query_project_resource_work_intentions
  session = ActionDispatch::Integration::Session.new(Rails.application)
  session.host! "localhost"
  session.post(
    "/graphql",
    params: {
      query: PROJECT_RESOURCE_WORK_INTENTION_DETAIL_QUERY,
      variables: {
        projectRef: @resource_browser_project_ref,
        intentionId: @expired_resource_browser_intention_id
      }
    },
    as: :json
  )
  assert_acceptance(session.response.status == 200, "Work-intention detail GraphQL returned HTTP #{session.response.status}")
  @resource_browser_intention_detail_payload = JSON.parse(session.response.body)
end

def query_project_resource_work_intentions
  session = ActionDispatch::Integration::Session.new(Rails.application)
  session.host! "localhost"
  session.post(
    "/graphql",
    params: {
      query: PROJECT_RESOURCE_BROWSER_QUERY,
      variables: { projectRef: @resource_browser_project_ref }
    },
    as: :json
  )
  assert_acceptance(session.response.status == 200, "Resource GraphQL returned HTTP #{session.response.status}")
  @resource_browser_payload = JSON.parse(session.response.body)
end

Then("only the agent with the active work intention is presented as an owner") do
  owners = resource_browser_work_intentions.map { [ _1.fetch("agentId"), _1.fetch("attemptId") ] }
  assert_acceptance_equal([ [ "luna-owner", "A-ui-owner" ] ], owners, "Active work-intention owners")
end

Then("every active membership is presented once while withdrawn and expired intentions are absent") do
  intentions = resource_browser_work_intentions
  paths = intentions.map { _1.fetch("resourcePath") }

  assert_acceptance_equal(%w[app/models/first.rb app/models/second.rb], paths.sort, "Active memberships")
  assert_acceptance_equal(paths.uniq, paths, "Unique active memberships")
  assert_acceptance(
    intentions.all? { _1.fetch("lastExpandedEventId") && _1.fetch("lastRenewedEventId") },
    "Expanded and renewed evidence must remain attached"
  )
  assert_acceptance(!intentions.any? { _1.fetch("agentId") == "luna-released" }, "Withdrawn intention set is active")
  assert_acceptance(!intentions.any? { _1.fetch("agentId") == "luna-expired" }, "Expired intention is active")
end

Then("the expired work-intention detail remains addressable as historical evidence") do
  errors = @resource_browser_intention_detail_payload.fetch("errors", [])
  assert_acceptance(errors.empty?, "Work-intention detail GraphQL failed: #{errors.inspect}")
  detail = @resource_browser_intention_detail_payload.dig("data", "projectResourceWorkIntention")
  assert_acceptance_equal(@expired_resource_browser_intention_id, detail.fetch("id"), "Expired intention identity")
  assert_acceptance_equal("EXPIRED", detail.fetch("status"), "Expired intention status")
  assert_acceptance_equal("luna-expired", detail.fetch("agentId"), "Expired intention owner")
end

Then("the old active work intention remains addressable in the browser") do
  intention = resource_browser_work_intentions.sole
  assert_acceptance_equal("A-ui-old-active", intention.fetch("attemptId"), "Retained active Attempt")
  assert_acceptance_equal("app/models/old_active.rb", intention.fetch("resourcePath"), "Retained resource")
end

def create_resource_browser_project
  @resource_browser_repository_id = SecureRandom.uuid_v7
  FactoryBot.create(
    :coordinator_read_repository,
    repository_id: @resource_browser_repository_id,
    repository_key: "resource-browser-#{@resource_browser_repository_id}",
    scope: "project:test/resource-browser-#{@resource_browser_repository_id}",
    display_name: "Resource browser"
  )
  @resource_browser_project_ref = Coordinator::Read::Web::ProjectReference.new.encode(
    scope: "project:test/resource-browser-#{@resource_browser_repository_id}"
  )
end

def create_resource_browser_resource(path)
  FactoryBot.create(
    :coordinator_read_resource,
    repository_id: @resource_browser_repository_id,
    normalized_path: path
  )
end

def create_resource_browser_attempt(
  attempt_id,
  agent_id,
  resource:,
  trait:,
  expanded_resource: nil,
  intention_id: SecureRandom.uuid_v7,
  expires_at: Time.utc(2099, 8, 31, 12)
)
  attributes = {
    attempt_id:,
    change_set_id: "CS-ui-resources",
    work_item_id: "W-#{attempt_id}",
    agent_id:,
    status: "started",
    base_snapshots: resource_browser_snapshots,
    work_intention_set_repository_id: @resource_browser_repository_id,
    work_intention_resource_id: resource.resource_id,
    work_intention_resource_path: resource.normalized_path,
    work_intention_id: intention_id,
    work_intention_set_id: SecureRandom.uuid_v7,
    work_intention_set_expires_at_domain: expires_at
  }
  if expanded_resource
    attributes[:expanded_resource_id] = expanded_resource.resource_id
    attributes[:expanded_resource_path] = expanded_resource.normalized_path
    attributes[:expanded_intention_id] = SecureRandom.uuid_v7
  end

  FactoryBot.create(:coordinator_read_attempt_history, trait, **attributes)
end

def resource_browser_snapshots
  [
    {
      "repository_id" => @resource_browser_repository_id,
      "object_format" => "sha1",
      "commit_oid" => "a" * 40
    }
  ]
end

def resource_browser_work_intentions
  errors = @resource_browser_payload.fetch("errors", [])
  assert_acceptance(errors.empty?, "Resource GraphQL failed: #{errors.inspect}")
  @resource_browser_payload.dig("data", "projectActiveResourceWorkIntentions", "nodes")
end
