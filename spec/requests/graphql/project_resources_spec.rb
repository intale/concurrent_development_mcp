# frozen_string_literal: true

RSpec.describe "GraphQL project resources", :read_model do
  QUERY = <<~GRAPHQL.freeze
    query ProjectResources(
      $repositoryId: ID!
      $first: Int
      $resourcesAfter: String
      $activeLeasesAfter: String
      $resourceKind: ResourceKind
      $resourceLifecycleStatus: ResourceLifecycleStatus
    ) {
      projectResources(
        repositoryId: $repositoryId
        first: $first
        resourcesAfter: $resourcesAfter
        activeLeasesAfter: $activeLeasesAfter
        resourceKind: $resourceKind
        resourceLifecycleStatus: $resourceLifecycleStatus
      ) {
        project { id name scope }
        resources {
          nodes { id repositoryId kind path lifecycleStatus unbindingReason registeredAt lastTransitionAt }
          pageInfo { endCursor hasNextPage }
        }
        activeLeases {
          asOf
          nodes {
            id leaseSetId resourceId resourceKind resourcePath resourceLifecycleStatus
            fencingToken policyVersion changeSetId workItemId attemptId agentId
            reservedEventId reservedAt expiresAt lastProjectedAt
          }
          pageInfo { endCursor hasNextPage }
        }
      }
    }
  GRAPHQL

  REPOSITORY_ID = "018f0f4d-4e45-7abc-8def-000000000061"
  RESOURCE_IDS = %w[
    018f0f4d-4e45-7abc-8def-000000000062
    018f0f4d-4e45-7abc-8def-000000000063
  ].freeze
  LEASE_ID = "018f0f4d-4e45-7abc-8def-000000000064"
  LEASE_SET_ID = "018f0f4d-4e45-7abc-8def-000000000065"

  before do
    create(
      :coordinator_read_repository,
      repository_id: REPOSITORY_ID,
      repository_key: "graphql-resources",
      scope: "project:graphql-resources",
      display_name: "GraphQL resources"
    )
    create(
      :coordinator_read_resource,
      resource_id: RESOURCE_IDS.fetch(0),
      repository_id: REPOSITORY_ID,
      normalized_path: "app/models/leased.rb"
    )
    create(
      :coordinator_read_resource,
      :inactive,
      resource_id: RESOURCE_IDS.fetch(1),
      repository_id: REPOSITORY_ID,
      normalized_path: "app/models/retired.rb"
    )
    create(
      :coordinator_read_attempt_history,
      :with_write_set,
      attempt_id: "A-resource-owner",
      change_set_id: "CS-resource-owner",
      work_item_id: "W-resource-owner",
      agent_id: "luna-owner",
      status: "started",
      base_snapshots: snapshots,
      write_set_resource_id: RESOURCE_IDS.fetch(0),
      write_set_resource_path: "app/models/leased.rb",
      write_set_lease_id: LEASE_ID,
      write_set_lease_set_id: LEASE_SET_ID,
      write_set_expires_at_domain: Time.utc(2099, 8, 31, 12)
    )
    create(
      :coordinator_read_attempt_history,
      attempt_id: "A-running-without-lease",
      change_set_id: "CS-running-without-lease",
      work_item_id: "W-running-without-lease",
      agent_id: "luna-blocked",
      status: "started",
      base_snapshots: snapshots
    )
  end

  it "serves projected inventory and identifies ownership only from active lease facts" do
    browser = execute(repositoryId: REPOSITORY_ID, first: 20).dig("data", "projectResources")

    expect(browser.dig("project", "id")).to eq(REPOSITORY_ID)
    expect(browser.dig("resources", "nodes").map { _1.fetch("id") }).to eq(RESOURCE_IDS)
    expect(browser.dig("activeLeases", "nodes").sole).to include(
      "id" => LEASE_ID,
      "resourceId" => RESOURCE_IDS.fetch(0),
      "workItemId" => "W-resource-owner",
      "attemptId" => "A-resource-owner",
      "agentId" => "luna-owner",
      "fencingToken" => "1"
    )
    expect(browser.dig("activeLeases", "nodes").to_s).not_to include("luna-blocked")
    expect(browser.dig("activeLeases", "asOf")).to match(Coordinator::Shared::Types::TIMESTAMP_PATTERN)
  end

  it "uses opaque, query-bound resource cursors and exact filters" do
    first = execute(repositoryId: REPOSITORY_ID, first: 1).dig("data", "projectResources", "resources")
    cursor = first.dig("pageInfo", "endCursor")

    expect(first.fetch("nodes").map { _1.fetch("id") }).to eq([ RESOURCE_IDS.fetch(0) ])
    expect(first.dig("pageInfo", "hasNextPage")).to be(true)
    expect(cursor).not_to include(RESOURCE_IDS.fetch(0))

    second = execute(
      repositoryId: REPOSITORY_ID,
      first: 1,
      resourcesAfter: cursor
    ).dig("data", "projectResources", "resources")
    expect(second.fetch("nodes").map { _1.fetch("id") }).to eq([ RESOURCE_IDS.fetch(1) ])

    mismatched = execute(
      repositoryId: REPOSITORY_ID,
      first: 1,
      resourcesAfter: cursor,
      resourceKind: "DIRECTORY"
    )
    expect(mismatched.dig("errors", 0, "extensions", "code")).to eq("INVALID_CURSOR")
  end

  it "returns null for an unprojected project and maps malformed input to a typed error" do
    missing = execute(repositoryId: "018f0f4d-4e45-7abc-8def-000000000099", first: 20)
    malformed = execute(repositoryId: "not-a-uuid", first: 20)

    expect(missing.dig("data", "projectResources")).to be_nil
    expect(malformed.dig("errors", 0, "extensions", "code")).to eq("INVALID_INPUT")
  end

  def snapshots
    [ { "repository_id" => REPOSITORY_ID, "object_format" => "sha1", "commit_oid" => "a" * 40 } ]
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
