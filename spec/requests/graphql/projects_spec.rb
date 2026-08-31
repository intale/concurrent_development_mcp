# frozen_string_literal: true

RSpec.describe "GraphQL project catalog", :read_model do
  PROJECTS_QUERY = <<~GRAPHQL.freeze
    query Projects($scope: String!, $first: Int, $after: String) {
      projects(scope: $scope, first: $first, after: $after) {
        nodes {
          id
          name
          paths
          registeredAt
          remotes
          scope
        }
        pageInfo {
          endCursor
          hasNextPage
        }
      }
    }
  GRAPHQL

  PROJECT_IDS = %w[
    018f0f4d-4e45-7abc-8def-000000000011
    018f0f4d-4e45-7abc-8def-000000000012
    018f0f4d-4e45-7abc-8def-000000000013
    018f0f4d-4e45-7abc-8def-000000000014
  ].freeze

  it "serves an exact scope through opaque bounded keyset pages" do
    PROJECT_IDS.each_with_index do |repository_id, index|
      create(
        :coordinator_read_repository,
        repository_id:,
        repository_key: "catalog-#{index}",
        scope: index == 3 ? "project:other" : "project:catalog"
      )
    end

    first = execute(scope: "project:catalog", first: 2).fetch("data").fetch("projects")
    expect(first.fetch("nodes").map { _1.fetch("id") }).to eq(PROJECT_IDS.first(2))
    expect(first.fetch("pageInfo")).to include("hasNextPage" => true)
    cursor = first.dig("pageInfo", "endCursor")
    expect(cursor).to be_present
    expect(cursor).not_to include(PROJECT_IDS.fetch(1))

    second = execute(scope: "project:catalog", first: 2, after: cursor).fetch("data").fetch("projects")
    expect(second.fetch("nodes").map { _1.fetch("id") }).to eq([ PROJECT_IDS.fetch(2) ])
    expect(second.fetch("pageInfo")).to eq("endCursor" => nil, "hasNextPage" => false)
  end

  it "returns an available empty page and never widens the caller's scope" do
    create(
      :coordinator_read_repository,
      repository_id: PROJECT_IDS.fetch(0),
      repository_key: "other",
      scope: "project:other"
    )

    projects = execute(scope: "project:missing", first: 20).fetch("data").fetch("projects")

    expect(projects).to eq(
      "nodes" => [],
      "pageInfo" => { "endCursor" => nil, "hasNextPage" => false }
    )
  end

  it "maps invalid cursors and invalid read-query input to typed GraphQL errors" do
    invalid_cursor = execute(scope: "project:catalog", first: 20, after: "not-a-cursor")
    invalid_limit = execute(scope: "project:catalog", first: 101)

    expect(invalid_cursor.dig("errors", 0, "extensions", "code")).to eq("INVALID_CURSOR")
    expect(invalid_limit.dig("errors", 0, "extensions", "code")).to eq("INVALID_INPUT")
  end

  it "publishes a query-only schema matching the committed client contract" do
    definition = Coordinator::Web::Graphql::Schema.to_definition

    expect(definition).to eq(Rails.root.join("app/graphql/schema.graphql").read)
    expect(definition).to include("type Query")
    expect(definition).not_to match(/^type (?:Mutation|Subscription)\b/)
  end

  def execute(scope:, first:, after: nil)
    variables = { scope:, first: }
    variables[:after] = after if after
    graphql_session.post "/graphql", params: { query: PROJECTS_QUERY, variables: }, as: :json
    expect(graphql_session.response.status).to eq(200), graphql_session.response.body
    graphql_session.response.parsed_body
  end

  def graphql_session
    @graphql_session ||= ActionDispatch::Integration::Session.new(Rails.application).tap do |session|
      session.host! "localhost"
    end
  end
end
