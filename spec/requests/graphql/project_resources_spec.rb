# frozen_string_literal: true

RSpec.describe "Project resource GraphQL", :read_model do
  RESOURCE_FIELDS = <<~GRAPHQL.freeze
    id
    repositoryId
    kind
    path
    lifecycleStatus
    unbindingReason
    registeredEventId
    registeredActorId
    registeredAt
    latestTransitionEventId
    latestTransitionActorId
    lastTransitionAt
  GRAPHQL
  LEASE_FIELDS = <<~GRAPHQL.freeze
    id
    leaseSetId
    resourceId
    repositoryId
    resourceKind
    resourcePath
    resourceLifecycleStatus
    status
    fencingToken
    changeSetId
    workItemId
    attemptId
    agentId
    reservedEventId
    releaseEventId
    reservedAt
    expiresAt
    releasedAt
    attemptTerminalAt
  GRAPHQL
  RESOURCES_QUERY = <<~GRAPHQL.freeze
    query ProjectResources(
      $projectRef: ID!
      $first: Int
      $after: String
      $path: String
      $resourceKind: ResourceKind
      $resourceLifecycleStatus: ResourceLifecycleStatus
    ) {
      projectResources(
        projectRef: $projectRef
        first: $first
        after: $after
        path: $path
        resourceKind: $resourceKind
        resourceLifecycleStatus: $resourceLifecycleStatus
      ) {
        nodes { #{RESOURCE_FIELDS} }
        pageInfo { endCursor hasNextPage }
      }
    }
  GRAPHQL
  RESOURCE_QUERY = <<~GRAPHQL.freeze
    query ProjectResource($projectRef: ID!, $resourceId: ID!) {
      projectResource(projectRef: $projectRef, resourceId: $resourceId) { #{RESOURCE_FIELDS} }
    }
  GRAPHQL
  LEASES_QUERY = <<~GRAPHQL.freeze
    query ProjectActiveResourceLeases(
      $projectRef: ID!
      $first: Int
      $after: String
      $agentId: String
      $changeSetId: ID
      $workItemId: ID
      $attemptId: ID
    ) {
      projectActiveResourceLeases(
        projectRef: $projectRef
        first: $first
        after: $after
        agentId: $agentId
        changeSetId: $changeSetId
        workItemId: $workItemId
        attemptId: $attemptId
      ) {
        asOf
        nodes { #{LEASE_FIELDS} }
        pageInfo { endCursor hasNextPage }
      }
    }
  GRAPHQL
  LEASE_QUERY = <<~GRAPHQL.freeze
    query ProjectResourceLease($projectRef: ID!, $leaseId: ID!) {
      projectResourceLease(projectRef: $projectRef, leaseId: $leaseId) { #{LEASE_FIELDS} }
    }
  GRAPHQL

  let(:scope) { "project:graphql-resources" }
  let(:project_ref) { Coordinator::Read::Web::ProjectReference.new.encode(scope:) }
  let(:repository_ids) do
    %w[
      018f0f4d-4e45-7abc-8def-000000000071
      018f0f4d-4e45-7abc-8def-000000000072
    ]
  end
  let(:resource_ids) do
    %w[
      018f0f4d-4e45-7abc-8def-000000000081
      018f0f4d-4e45-7abc-8def-000000000082
      018f0f4d-4e45-7abc-8def-000000000083
    ]
  end
  let(:lease_ids) do
    %w[
      018f0f4d-4e45-7abc-8def-000000000091
      018f0f4d-4e45-7abc-8def-000000000092
    ]
  end

  before do
    repository_ids.each_with_index do |repository_id, index|
      create(
        :coordinator_read_repository,
        repository_id:,
        repository_key: "graphql-resources-#{index}",
        scope:
      )
    end
    create(
      :coordinator_read_repository,
      repository_id: "018f0f4d-4e45-7abc-8def-000000000079",
      repository_key: "graphql-resources-outside",
      scope: "project:outside"
    )
    create_resource(resource_ids.fetch(0), repository_ids.fetch(0), "app/models/alpha.rb")
    create_resource(resource_ids.fetch(1), repository_ids.fetch(1), "app/services/beta.rb")
    @outside_resource = create_resource(
      resource_ids.fetch(2),
      "018f0f4d-4e45-7abc-8def-000000000079",
      "private/outside.rb"
    )
    create_lease("A-held", resource_ids.fetch(0), lease_ids.fetch(0), "luna-owner", Time.utc(2099, 1, 1))
    create_lease("A-expired", resource_ids.fetch(1), lease_ids.fetch(1), "luna-former", Time.utc(2020, 1, 1))
  end

  it "pages exact-Project resources with opaque filter-bound cursors" do
    first = execute(RESOURCES_QUERY, projectRef: project_ref, first: 1).dig("data", "projectResources")
    cursor = first.dig("pageInfo", "endCursor")
    second = execute(
      RESOURCES_QUERY,
      projectRef: project_ref,
      first: 1,
      after: cursor
    ).dig("data", "projectResources")
    mismatched = execute(
      RESOURCES_QUERY,
      projectRef: project_ref,
      first: 1,
      after: cursor,
      path: "services"
    )

    expect(first.fetch("nodes").map { _1.fetch("id") }).to eq([ resource_ids.fetch(0) ])
    expect(first.dig("pageInfo", "hasNextPage")).to be(true)
    expect(cursor).not_to include(resource_ids.fetch(0))
    expect(second.fetch("nodes").map { _1.fetch("id") }).to eq([ resource_ids.fetch(1) ])
    expect(mismatched.dig("errors", 0, "extensions", "code")).to eq("INVALID_CURSOR")
  end

  it "exposes ResourceGet detail evidence only inside the exact Project" do
    detail = execute(
      RESOURCE_QUERY,
      projectRef: project_ref,
      resourceId: resource_ids.fetch(0)
    ).dig("data", "projectResource")
    hidden = execute(
      RESOURCE_QUERY,
      projectRef: project_ref,
      resourceId: @outside_resource.resource_id
    ).dig("data", "projectResource")

    expect(detail).to include(
      "id" => resource_ids.fetch(0),
      "repositoryId" => repository_ids.fetch(0),
      "path" => "app/models/alpha.rb",
      "registeredActorId" => "factory-agent"
    )
    expect(detail.fetch("registeredEventId")).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(hidden).to be_nil
  end

  it "filters factual active leases and keeps an expired lease detail addressable" do
    active = execute(
      LEASES_QUERY,
      projectRef: project_ref,
      first: 20,
      agentId: "luna-owner",
      workItemId: "W-A-held"
    ).dig("data", "projectActiveResourceLeases")
    expired = execute(
      LEASE_QUERY,
      projectRef: project_ref,
      leaseId: lease_ids.fetch(1)
    ).dig("data", "projectResourceLease")

    expect(active.fetch("nodes").sole).to include(
      "id" => lease_ids.fetch(0),
      "status" => "ACTIVE",
      "agentId" => "luna-owner"
    )
    expect(active.fetch("asOf")).to match(Coordinator::Shared::Types::TIMESTAMP_PATTERN)
    expect(expired).to include(
      "id" => lease_ids.fetch(1),
      "status" => "EXPIRED",
      "agentId" => "luna-former"
    )
  end

  it "maps malformed Project references and Resource identifiers to typed errors" do
    bad_project = execute(RESOURCES_QUERY, projectRef: "not-a-project", first: 20)
    bad_resource = execute(RESOURCE_QUERY, projectRef: project_ref, resourceId: "not-a-resource")

    expect(bad_project.dig("errors", 0, "extensions", "code")).to eq("INVALID_PROJECT_REFERENCE")
    expect(bad_resource.dig("errors", 0, "extensions", "code")).to eq("INVALID_INPUT")
  end

  def create_resource(resource_id, repository_id, path)
    create(:coordinator_read_resource, resource_id:, repository_id:, normalized_path: path)
  end

  def create_lease(attempt_id, resource_id, lease_id, agent_id, expires_at)
    resource = Coordinator::Read::Resource.find(resource_id)
    create(
      :coordinator_read_attempt_history,
      :with_write_set,
      attempt_id:,
      change_set_id: "CS-graphql-resources",
      work_item_id: "W-#{attempt_id}",
      agent_id:,
      status: "started",
      base_snapshots: [
        { "repository_id" => resource.repository_id, "object_format" => "sha1", "commit_oid" => "a" * 40 }
      ],
      write_set_repository_id: resource.repository_id,
      write_set_resource_id: resource_id,
      write_set_resource_path: resource.normalized_path,
      write_set_lease_id: lease_id,
      write_set_lease_set_id: SecureRandom.uuid_v7,
      write_set_expires_at_domain: expires_at
    )
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
end
