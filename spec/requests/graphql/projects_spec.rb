# frozen_string_literal: true

module ProjectCatalogGraphqlSpec
  RSpec.describe "GraphQL Project catalog", :read_model do
    PROJECTS_QUERY = <<~GRAPHQL.freeze
      query Projects($search: String, $sort: ProjectSort, $first: Int, $after: String, $repositoriesFirst: Int) {
        projects(
          search: $search
          sort: $sort
          first: $first
          after: $after
          repositoriesFirst: $repositoriesFirst
        ) {
          nodes {
            projectRef
            displayLabel
            repositoryCount
            scope
            repositories {
              nodes { id displayName paths registeredAt remotes }
              totalCount
              pageInfo { endCursor hasNextPage }
            }
          }
          pageInfo { endCursor hasNextPage }
        }
      }
    GRAPHQL

    PROJECT_QUERY = <<~GRAPHQL.freeze
      query Project($projectRef: ID!, $first: Int, $after: String) {
        project(projectRef: $projectRef, repositoriesFirst: $first, repositoriesAfter: $after) {
          projectRef
          displayLabel
          repositoryCount
          scope
          repositories {
            nodes { id displayName paths registeredAt remotes }
            totalCount
            pageInfo { endCursor hasNextPage }
          }
        }
      }
    GRAPHQL

    REPOSITORY_IDS = %w[
      018f0f4d-4e45-7abc-8def-000000000081
      018f0f4d-4e45-7abc-8def-000000000082
      018f0f4d-4e45-7abc-8def-000000000083
      018f0f4d-4e45-7abc-8def-000000000084
    ].freeze

    before do
      create_repository(0, scope: "project:alpha", name: "Alpha API", path: "/work/alpha/api")
      create_repository(1, scope: "project:alpha", name: "Alpha Web", path: "/work/alpha/web")
      create_repository(2, scope: "project:alpha", name: "Alpha Jobs", path: "/work/alpha/jobs")
      create_repository(3, scope: "project:beta", name: "Beta", path: "/searchable/beta")
    end

    it "discovers Projects without caller scope knowledge through bounded keyset pages" do
      first = execute_projects(first: 1, repositories_first: 2).dig("data", "projects")
      project = first.fetch("nodes").first

      expect(project).to include(
        "scope" => "project:alpha",
        "displayLabel" => "project:alpha",
        "repositoryCount" => 3
      )
      expect(project_reference.decode(project.fetch("projectRef"))).to eq("project:alpha")
      expect(project.fetch("projectRef")).not_to include("project:alpha")
      expect(project.dig("repositories", "nodes").map { _1.fetch("id") }).to eq(REPOSITORY_IDS.first(2))
      expect(project.fetch("repositories")).to include("totalCount" => 3)
      expect(project.dig("repositories", "pageInfo", "hasNextPage")).to be(true)
      expect(first.fetch("pageInfo")).to include("hasNextPage" => true)

      second = execute_projects(first: 1, after: first.dig("pageInfo", "endCursor")).dig("data", "projects")
      expect(second.fetch("nodes").map { _1.fetch("scope") }).to eq([ "project:beta" ])
      expect(second.fetch("pageInfo")).to eq("endCursor" => nil, "hasNextPage" => false)
    end

    it "searches available Repository display and path data on the server" do
      by_name = execute_projects(search: "ALPHA JOBS").dig("data", "projects", "nodes")
      by_path = execute_projects(search: "searchable").dig("data", "projects", "nodes")

      expect(by_name.map { _1.fetch("scope") }).to eq([ "project:alpha" ])
      expect(by_path.map { _1.fetch("scope") }).to eq([ "project:beta" ])
    end

    it "rejects a Project cursor when its filter or sort changes" do
      cursor = execute_projects(first: 1).dig("data", "projects", "pageInfo", "endCursor")
      mismatch = execute_projects(first: 1, after: cursor, search: "alpha")

      expect(mismatch.dig("errors", 0, "extensions", "code")).to eq("INVALID_CURSOR")
    end

    it "resolves an opaque Project reference and pages its explicit Repository members" do
      project_ref = project_reference.encode(scope: "project:alpha")
      first = execute_project(project_ref:, first: 2).dig("data", "project")
      second = execute_project(
        project_ref:,
        first: 2,
        after: first.dig("repositories", "pageInfo", "endCursor")
      ).dig("data", "project")

      expect(first).to include(
        "projectRef" => project_ref,
        "scope" => "project:alpha",
        "repositoryCount" => 3
      )
      expect(first.dig("repositories", "nodes").map { _1.fetch("id") }).to eq(REPOSITORY_IDS.first(2))
      expect(second.dig("repositories", "nodes").map { _1.fetch("id") }).to eq([ REPOSITORY_IDS.fetch(2) ])
      expect(second.dig("repositories", "pageInfo")).to eq("endCursor" => nil, "hasNextPage" => false)
    end

    it "maps invalid references and input to typed errors while unknown Projects remain recoverable" do
      invalid = execute_project(project_ref: "not-a-reference", first: 20)
      invalid_limit = execute_projects(first: 101)
      missing = execute_project(
        project_ref: project_reference.encode(scope: "project:missing"),
        first: 20
      )

      expect(invalid.dig("errors", 0, "extensions", "code")).to eq("INVALID_PROJECT_REFERENCE")
      expect(invalid_limit.dig("errors", 0, "extensions", "code")).to eq("INVALID_INPUT")
      expect(missing.dig("data", "project")).to be_nil
    end

    it "serves old available Project data and an available empty catalog" do
      stale = execute_projects(search: "beta").dig("data", "projects", "nodes", 0)
      Coordinator::Read::Repository.delete_all
      empty = execute_projects.dig("data", "projects")

      expect(stale.dig("repositories", "nodes", 0, "registeredAt")).to eq(
        "2020-01-01T12:00:00.000000Z"
      )
      expect(empty).to eq(
        "nodes" => [],
        "pageInfo" => { "endCursor" => nil, "hasNextPage" => false }
      )
    end

    it "publishes a query-only schema matching the committed client contract" do
      definition = Coordinator::Web::Graphql::Schema.to_definition

      expect(definition).to eq(Rails.root.join("app/graphql/schema.graphql").read)
      expect(definition).to include("type Query")
      expect(definition).not_to match(/^type (?:Mutation|Subscription)\b/)
    end

    def execute_projects(first: 20, repositories_first: 3, search: nil, sort: "SCOPE_ASC", after: nil)
      execute(
        PROJECTS_QUERY,
        search:,
        sort:,
        first:,
        after:,
        repositoriesFirst: repositories_first
      )
    end

    def execute_project(project_ref:, first:, after: nil)
      execute(PROJECT_QUERY, projectRef: project_ref, first:, after:)
    end

    def execute(query, variables)
      graphql_session.post "/graphql", params: { query:, variables: }, as: :json
      expect(graphql_session.response.status).to eq(200), graphql_session.response.body
      graphql_session.response.parsed_body
    end

    def graphql_session
      @graphql_session ||= ActionDispatch::Integration::Session.new(Rails.application).tap do |session|
        session.host! "localhost"
      end
    end

    def project_reference
      @project_reference ||= Coordinator::Read::Web::ProjectReference.new
    end

    def create_repository(index, scope:, name:, path:)
      create(
        :coordinator_read_repository,
        repository_id: REPOSITORY_IDS.fetch(index),
        repository_key: "graphql-project-#{index}",
        scope:,
        display_name: name,
        paths: [ path ],
        registered_at_domain: Time.utc(2020, 1, 1, 12)
      )
    end
  end
end
