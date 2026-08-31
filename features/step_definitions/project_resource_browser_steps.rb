# frozen_string_literal: true

PROJECT_RESOURCE_BROWSER_QUERY = <<~GRAPHQL.freeze
  query ProjectResourceBrowser($repositoryId: ID!) {
    projectResources(repositoryId: $repositoryId, first: 100) {
      resources { nodes { id path } }
      activeLeases {
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
  }
GRAPHQL

Given("projected resource rows contain two running agents but only one active lease") do
  create_resource_browser_project
  leased = create_resource_browser_resource("app/models/owned.rb")
  create_resource_browser_attempt(
    "A-ui-owner",
    "luna-owner",
    resource: leased,
    trait: :with_write_set
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

Given("projected resource rows represent expanded renewed and released lease lifecycles after redelivery") do
  create_resource_browser_project
  first = create_resource_browser_resource("app/models/first.rb")
  second = create_resource_browser_resource("app/models/second.rb")
  released_first = create_resource_browser_resource("app/models/released_first.rb")
  released_second = create_resource_browser_resource("app/models/released_second.rb")

  create_resource_browser_attempt(
    "A-ui-lifecycle-active",
    "luna-active",
    resource: first,
    expanded_resource: second,
    trait: :expanded_and_renewed_write_set
  )
  create_resource_browser_attempt(
    "A-ui-lifecycle-released",
    "luna-released",
    resource: released_first,
    expanded_resource: released_second,
    trait: :completed_write_set_lifecycle
  )
end

Given("projected resource rows retain an old active lease and one hundred one newer terminal Attempts") do
  create_resource_browser_project
  resource = create_resource_browser_resource("app/models/old_active.rb")
  create_resource_browser_attempt(
    "A-ui-old-active",
    "luna-old-active",
    resource:,
    trait: :with_write_set
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

When("the browser queries the projected project resources") do
  session = ActionDispatch::Integration::Session.new(Rails.application)
  session.host! "localhost"
  session.post(
    "/graphql",
    params: {
      query: PROJECT_RESOURCE_BROWSER_QUERY,
      variables: { repositoryId: @resource_browser_repository_id }
    },
    as: :json
  )
  assert_acceptance(session.response.status == 200, "Resource GraphQL returned HTTP #{session.response.status}")
  @resource_browser_payload = JSON.parse(session.response.body)
end

Then("only the agent with the active lease is presented as the owner") do
  owners = resource_browser_leases.map { [ _1.fetch("agentId"), _1.fetch("attemptId") ] }
  assert_acceptance_equal([ [ "luna-owner", "A-ui-owner" ] ], owners, "Active lease owners")
end

Then("every active membership is presented once and the released set is absent") do
  leases = resource_browser_leases
  paths = leases.map { _1.fetch("resourcePath") }

  assert_acceptance_equal(%w[app/models/first.rb app/models/second.rb], paths.sort, "Active memberships")
  assert_acceptance_equal(paths.uniq, paths, "Unique active memberships")
  assert_acceptance(
    leases.all? { _1.fetch("lastExpandedEventId") && _1.fetch("lastRenewedEventId") },
    "Expanded and renewed evidence must remain attached"
  )
  assert_acceptance(!leases.any? { _1.fetch("agentId") == "luna-released" }, "Released lease set is active")
end

Then("the old active lease remains addressable in the browser") do
  lease = resource_browser_leases.sole
  assert_acceptance_equal("A-ui-old-active", lease.fetch("attemptId"), "Retained active Attempt")
  assert_acceptance_equal("app/models/old_active.rb", lease.fetch("resourcePath"), "Retained resource")
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
end

def create_resource_browser_resource(path)
  FactoryBot.create(
    :coordinator_read_resource,
    repository_id: @resource_browser_repository_id,
    normalized_path: path
  )
end

def create_resource_browser_attempt(attempt_id, agent_id, resource:, trait:, expanded_resource: nil)
  attributes = {
    attempt_id:,
    change_set_id: "CS-ui-resources",
    work_item_id: "W-#{attempt_id}",
    agent_id:,
    status: "started",
    base_snapshots: resource_browser_snapshots,
    write_set_repository_id: @resource_browser_repository_id,
    write_set_resource_id: resource.resource_id,
    write_set_resource_path: resource.normalized_path,
    write_set_lease_id: SecureRandom.uuid_v7,
    write_set_lease_set_id: SecureRandom.uuid_v7,
    write_set_expires_at_domain: Time.utc(2099, 8, 31, 12)
  }
  if expanded_resource
    attributes[:expanded_resource_id] = expanded_resource.resource_id
    attributes[:expanded_resource_path] = expanded_resource.normalized_path
    attributes[:expanded_lease_id] = SecureRandom.uuid_v7
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

def resource_browser_leases
  errors = @resource_browser_payload.fetch("errors", [])
  assert_acceptance(errors.empty?, "Resource GraphQL failed: #{errors.inspect}")
  @resource_browser_payload.dig("data", "projectResources", "activeLeases", "nodes")
end
