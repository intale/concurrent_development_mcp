# frozen_string_literal: true

PROJECT_CATALOG_QUERY = <<~GRAPHQL.freeze
  query Projects($scope: String!, $first: Int, $after: String) {
    projects(scope: $scope, first: $first, after: $after) {
      nodes {
        id
        name
        scope
      }
      pageInfo {
        endCursor
        hasNextPage
      }
    }
  }
GRAPHQL

Given(
  "exact project scope {string} has registered repository {string}"
) do |scope, repository_key|
  @project_catalog_repositories ||= {}
  repository_id = register_project_catalog_repository(scope:, repository_key:)
  @project_catalog_repositories[repository_key] = repository_id
  await_read_model("Repository #{repository_key} to reach GraphQL") do
    payload = query_project_catalog(scope)
    [ project_catalog_ids(payload).include?(repository_id), payload ]
  end
end

When("the browser queries the project catalog for {string}") do |scope|
  @project_catalog_scope = scope
  @project_catalog_payload = query_project_catalog(scope)
end

Then("the project catalog contains only repository {string}") do |repository_key|
  expected_id = @project_catalog_repositories.fetch(repository_key)
  assert_acceptance_equal([ expected_id ], project_catalog_ids(@project_catalog_payload), "Scoped project catalog")
  assert_acceptance_equal(
    [ @project_catalog_scope ],
    @project_catalog_payload.dig("data", "projects", "nodes").map { _1.fetch("scope") }.uniq,
    "Exact project scopes"
  )
end

Then("Rails serves the standalone project browser shell") do
  session = ActionDispatch::Integration::Session.new(Rails.application).tap do |browser|
    browser.host! "localhost"
  end
  session.get("/projects")

  assert_acceptance(session.response.status == 200, "UI shell returned HTTP #{session.response.status}")
  assert_acceptance(
    session.response.body.include?('data-react-class="CoordinatorApp"'),
    "UI shell did not expose the react-rails component mount"
  )
  assert_acceptance(
    !session.response.body.include?("data-hydrate"),
    "UI shell unexpectedly enabled server-side React rendering"
  )
end

Then("every project browser route serves the same standalone shell") do
  repository_id = @project_catalog_repositories.fetch("ui-catalog-a")
  paths = %w[coordination resources knowledge governance delivery].map do |section|
    "/projects/#{repository_id}/#{section}"
  end
  session = ActionDispatch::Integration::Session.new(Rails.application).tap do |browser|
    browser.host! "localhost"
  end

  paths.each do |path|
    session.get(path)
    assert_acceptance(session.response.status == 200, "#{path} returned HTTP #{session.response.status}")
    assert_acceptance(
      session.response.body.include?('data-react-class="CoordinatorApp"'),
      "#{path} did not expose the react-rails component mount"
    )
  end
end

Then("the browser-facing GraphQL schema exposes Query without Mutation or Subscription") do
  payload = project_catalog_graphql_request(
    <<~GRAPHQL,
      query ProjectCatalogSchema {
        __schema {
          queryType { name }
          mutationType { name }
          subscriptionType { name }
        }
      }
    GRAPHQL
    {}
  )
  schema = payload.dig("data", "__schema")
  assert_acceptance_equal("Query", schema.dig("queryType", "name"), "GraphQL Query root")
  assert_acceptance_equal(nil, schema.fetch("mutationType"), "GraphQL Mutation root")
  assert_acceptance_equal(nil, schema.fetch("subscriptionType"), "GraphQL Subscription root")
end

When(
  "project-catalog projection delivery pauses and repository {string} registers in that scope"
) do |repository_key|
  @project_catalog_scope = "project:test/ui-catalog-stale"
  stop_read_model_subscriptions
  @project_catalog_repositories ||= {}
  repository_id = register_project_catalog_repository(
    scope: @project_catalog_scope,
    repository_key:
  )
  @project_catalog_repositories[repository_key] = repository_id
  @project_catalog_stale_payload = query_project_catalog(@project_catalog_scope)
end

Then("the project catalog remains available with repository {string}") do |repository_key|
  expected_id = @project_catalog_repositories.fetch(repository_key)
  assert_acceptance_equal(
    [ expected_id ],
    project_catalog_ids(@project_catalog_stale_payload),
    "Available stale project catalog"
  )
end

Then("the unprojected repository {string} is not presented as current") do |repository_key|
  repository_id = @project_catalog_repositories.fetch(repository_key)
  assert_acceptance(
    !project_catalog_ids(@project_catalog_stale_payload).include?(repository_id),
    "Unprojected repository was presented as current"
  )
end

When("project-catalog projection delivery restarts") do
  restart_read_model_subscriptions
end

Then(
  "the project catalog eventually contains repositories {string} and {string}"
) do |first_key, second_key|
  expected_ids = [ first_key, second_key ].map { @project_catalog_repositories.fetch(_1) }.sort
  @project_catalog_converged_payload = eventually("project catalog to converge") do
    payload = query_project_catalog(@project_catalog_scope)
    [ project_catalog_ids(payload).sort == expected_ids, payload ]
  end
  assert_acceptance_equal(
    expected_ids,
    project_catalog_ids(@project_catalog_converged_payload).sort,
    "Converged project catalog"
  )
end

def register_project_catalog_repository(scope:, repository_key:)
  repository_id = SecureRandom.uuid_v7
  submit_and_execute(
    "repository_register",
    client_id: "project-catalog-browser",
    command_id: "cuc-ui-project-register-#{repository_id}",
    actor: { kind: "agent", id: "project-catalog-agent" },
    repository_id:,
    scope:,
    repository_key:,
    display_name: repository_key.titleize,
    paths: [],
    remotes: []
  )
  repository_id
end

def query_project_catalog(scope)
  project_catalog_graphql_request(
    PROJECT_CATALOG_QUERY,
    { scope:, first: 20 }
  )
end

def project_catalog_graphql_request(query, variables)
  @project_catalog_graphql_session ||= ActionDispatch::Integration::Session.new(Rails.application).tap do |session|
    session.host! "localhost"
  end
  @project_catalog_graphql_session.post(
    "/graphql",
    params: { query:, variables: },
    as: :json
  )
  response = @project_catalog_graphql_session.response
  assert_acceptance(response.status == 200, "GraphQL returned HTTP #{response.status}: #{response.body}")
  JSON.parse(response.body)
end

def project_catalog_ids(payload)
  errors = payload.fetch("errors", [])
  assert_acceptance(errors.empty?, "GraphQL project catalog failed: #{errors.inspect}")
  payload.dig("data", "projects", "nodes").map { _1.fetch("id") }
end
