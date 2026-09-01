# frozen_string_literal: true

module ProjectCoordinationGraphqlSpec
  RSpec.describe "GraphQL project coordination", :read_model do
  let(:repository_id) { "018f0f4d-4e45-7abc-8def-000000000031" }
  QUERY = <<~GRAPHQL.freeze
    query ProjectCoordination($repositoryId: ID!, $first: Int, $workItemsAfter: String) {
      projectCoordination(repositoryId: $repositoryId, first: $first, workItemsAfter: $workItemsAfter) {
        project { id name scope }
        changeSets { nodes { id goal acceptanceCriteria domainStatus runningWorkItemCount } pageInfo { endCursor hasNextPage } }
        workItems {
          nodes { id domainStatus presentationStatus activeAgentId activeAttemptId attemptStatus attemptStartedAt }
          pageInfo { endCursor hasNextPage }
        }
        dependencies { nodes { id producerWorkItemId consumerWorkItemId blocking } pageInfo { endCursor hasNextPage } }
      }
    }
  GRAPHQL

  before do
    create(
      :coordinator_read_repository,
      repository_id:,
      repository_key: "graphql-dashboard",
      scope: "project:graphql-dashboard"
    )
    context = build(
      :coordinator_read_coord_context,
      change_set_id: "CS-graphql-dashboard",
      repository_id:,
      work_item_id: "W-graphql-running",
      attempt_id: "A-graphql-running"
    )
    context.document["attempts"] = []
    context.save!
    create(
      :coordinator_read_attempt_history,
      attempt_id: "A-graphql-running",
      change_set_id: "CS-graphql-dashboard",
      work_item_id: "W-graphql-running",
      agent_id: "luna-graphql",
      status: "started",
      started_at_domain: Time.utc(2026, 8, 31, 13)
    )
  end

  it "serves typed latest coordination facts through the semantic query" do
    payload = execute(repositoryId: repository_id, first: 20)
    dashboard = payload.dig("data", "projectCoordination")

    expect(dashboard.dig("project", "id")).to eq(repository_id)
    expect(dashboard.dig("workItems", "nodes").sole).to include(
      "id" => "W-graphql-running",
      "domainStatus" => "acquired",
      "presentationStatus" => "RUNNING",
      "activeAgentId" => "luna-graphql",
      "activeAttemptId" => "A-graphql-running",
      "attemptStatus" => "started"
    )
  end

  it "maps malformed collection cursors to a typed error" do
    payload = execute(repositoryId: repository_id, first: 20, workItemsAfter: "invalid")

    expect(payload.dig("errors", 0, "extensions", "code")).to eq("INVALID_CURSOR")
  end

  it "returns null rather than fabricating an unprojected project" do
    payload = execute(repositoryId: "018f0f4d-4e45-7abc-8def-000000000099", first: 20)

    expect(payload.dig("data", "projectCoordination")).to be_nil
  end

  def execute(variables)
    graphql_session.post "/graphql", params: { query: QUERY, variables: }, as: :json
    expect(graphql_session.response.status).to eq(200), graphql_session.response.body
    graphql_session.response.parsed_body
  end

  def graphql_session
    @graphql_session ||= ActionDispatch::Integration::Session.new(Rails.application).tap do |session|
      session.host! "localhost"
    end
  end
  end
end
