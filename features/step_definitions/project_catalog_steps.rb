# frozen_string_literal: true

PROJECT_CATALOG_QUERY = <<~GRAPHQL.freeze
  query Projects($search: String, $first: Int, $repositoriesFirst: Int) {
    projects(search: $search, first: $first, repositoriesFirst: $repositoriesFirst) {
      nodes {
        projectRef
        displayLabel
        scope
        repositoryCount
        repositories {
          nodes {
            id
            displayName
            paths
          }
        }
      }
      pageInfo {
        endCursor
        hasNextPage
      }
    }
  }
GRAPHQL

Given(
  "exact project scope {string} has projected repository {string}"
) do |scope, repository_key|
  project_catalog_create_repository(scope:, repository_key:)
end

When("the browser queries the project catalog for {string}") do |scope|
  @project_catalog_scope = scope
  @project_catalog_payload = query_project_catalog(scope)
end

Then("the project catalog contains only repository {string}") do |repository_key|
  expected_id = @project_catalog_repositories.fetch(repository_key).repository_id
  assert_acceptance_equal(
    [ expected_id ],
    project_catalog_repository_ids(@project_catalog_payload),
    "Scoped project catalog"
  )
  assert_acceptance_equal(
    [ @project_catalog_scope ],
    project_catalog_projects(@project_catalog_payload).map { _1.fetch("scope") }.uniq,
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
  project_ref = project_catalog_projects(@project_catalog_payload).fetch(0).fetch("projectRef")
  paths = %w[coordination resources knowledge governance delivery].map do |section|
    "/projects/#{project_ref}/#{section}"
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

When("the browser reads that project before repository {string} is projected") do |repository_key|
  @project_catalog_scope = @project_catalog_repositories.values.fetch(0).scope
  @project_catalog_pending_repository_key = repository_key
  @project_catalog_stale_payload = query_project_catalog(@project_catalog_scope)
end

Then("the project catalog remains available with repository {string}") do |repository_key|
  expected_id = @project_catalog_repositories.fetch(repository_key).repository_id
  assert_acceptance_equal(
    [ expected_id ],
    project_catalog_repository_ids(@project_catalog_stale_payload),
    "Available prior project catalog"
  )
end

Then("the unprojected repository {string} is not presented as current") do |repository_key|
  assert_acceptance_equal(@project_catalog_pending_repository_key, repository_key, "Pending Repository")
  assert_acceptance(
    @project_catalog_stale_payload.to_s.exclude?(repository_key),
    "Unprojected Repository was presented as current"
  )
end

When("repository {string} becomes available in that Project projection") do |repository_key|
  project_catalog_create_repository(scope: @project_catalog_scope, repository_key:)
end

Then(
  "the project catalog contains repositories {string} and {string}"
) do |first_key, second_key|
  expected_ids = [ first_key, second_key ].map do |key|
    @project_catalog_repositories.fetch(key).repository_id
  end.sort
  payload = query_project_catalog(@project_catalog_scope)
  assert_acceptance_equal(
    expected_ids,
    project_catalog_repository_ids(payload).sort,
    "Latest available project catalog"
  )
end

def project_catalog_create_repository(scope:, repository_key:)
  @project_catalog_repositories ||= {}
  @project_catalog_repositories[repository_key] = FactoryBot.create(
    :coordinator_read_repository,
    scope:,
    repository_key:
  )
end

def query_project_catalog(search)
  project_catalog_graphql_request(
    PROJECT_CATALOG_QUERY,
    { search:, first: 20, repositoriesFirst: 20 }
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

def project_catalog_projects(payload)
  errors = payload.fetch("errors", [])
  assert_acceptance(errors.empty?, "GraphQL project catalog failed: #{errors.inspect}")
  payload.dig("data", "projects", "nodes")
end

def project_catalog_repository_ids(payload)
  project_catalog_projects(payload).flat_map do |project|
    project.dig("repositories", "nodes").map { _1.fetch("id") }
  end
end
