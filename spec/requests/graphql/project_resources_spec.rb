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
  WORK_INTENTION_FIELDS = <<~GRAPHQL.freeze
    id
    intentionSetId
    resourceId
    repositoryId
    resourceKind
    resourcePath
    resourceLifecycleStatus
    status
    mode
    purpose
    context
    fencingToken
    changeSetId
    workItemId
    attemptId
    agentId
    declaredEventId
    withdrawalEventId
    declaredAt
    expiresAt
    withdrawnAt
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
      $sort: LatestUpdateSort
    ) {
      projectResources(
        projectRef: $projectRef
        first: $first
        after: $after
        path: $path
        resourceKind: $resourceKind
        resourceLifecycleStatus: $resourceLifecycleStatus
        sort: $sort
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
  WORK_INTENTIONS_QUERY = <<~GRAPHQL.freeze
    query ProjectActiveResourceWorkIntentions(
      $projectRef: ID!
      $first: Int
      $after: String
      $agentId: String
      $changeSetId: ID
      $workItemId: ID
      $attemptId: ID
      $mode: ResourceWorkIntentionMode
      $sort: LatestUpdateSort
    ) {
      projectActiveResourceWorkIntentions(
        projectRef: $projectRef
        first: $first
        after: $after
        agentId: $agentId
        changeSetId: $changeSetId
        workItemId: $workItemId
        attemptId: $attemptId
        mode: $mode
        sort: $sort
      ) {
        asOf
        nodes { #{WORK_INTENTION_FIELDS} }
        pageInfo { endCursor hasNextPage }
      }
    }
  GRAPHQL
  WORK_INTENTION_QUERY = <<~GRAPHQL.freeze
    query ProjectResourceWorkIntention($projectRef: ID!, $intentionId: ID!) {
      projectResourceWorkIntention(projectRef: $projectRef, intentionId: $intentionId) { #{WORK_INTENTION_FIELDS} }
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
  let(:intention_ids) do
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
    create_work_intention("A-held", resource_ids.fetch(0), intention_ids.fetch(0), "luna-owner", Time.utc(2099, 1, 1))
    create_work_intention("A-expired", resource_ids.fetch(1), intention_ids.fetch(1), "luna-former", Time.utc(2020, 1, 1))
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
    oldest = execute(
      RESOURCES_QUERY,
      projectRef: project_ref,
      first: 1,
      sort: "OLDEST_FIRST"
    ).dig("data", "projectResources")

    expect(first.fetch("nodes").map { _1.fetch("id") }).to eq([ resource_ids.fetch(0) ])
    expect(first.dig("pageInfo", "hasNextPage")).to be(true)
    expect(cursor).not_to include(resource_ids.fetch(0))
    expect(second.fetch("nodes").map { _1.fetch("id") }).to eq([ resource_ids.fetch(1) ])
    expect(oldest.fetch("nodes").map { _1.fetch("id") }).to eq([ resource_ids.fetch(1) ])
    expect(mismatched.dig("errors", 0, "extensions", "code")).to eq("INVALID_CURSOR")
    expect(
      execute(
        RESOURCES_QUERY,
        projectRef: project_ref,
        first: 1,
        after: cursor,
        sort: "OLDEST_FIRST"
      ).dig("errors", 0, "extensions", "code")
    ).to eq("INVALID_CURSOR")
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

  it "filters active advisory work intentions and keeps expired detail addressable" do
    active = execute(
      WORK_INTENTIONS_QUERY,
      projectRef: project_ref,
      first: 20,
      agentId: "luna-owner",
      workItemId: "W-A-held",
      mode: "SHARED"
    ).dig("data", "projectActiveResourceWorkIntentions")
    expired = execute(
      WORK_INTENTION_QUERY,
      projectRef: project_ref,
      intentionId: intention_ids.fetch(1)
    ).dig("data", "projectResourceWorkIntention")

    expect(active.fetch("nodes").sole).to include(
      "id" => intention_ids.fetch(0),
      "status" => "ACTIVE",
      "agentId" => "luna-owner",
      "mode" => "SHARED",
      "purpose" => "Implement A-held",
      "context" => "Keep the intent visible to peers"
    )
    expect(active.fetch("asOf")).to match(Coordinator::Shared::Types::TIMESTAMP_PATTERN)
    expect(expired).to include(
      "id" => intention_ids.fetch(1),
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
    index = resource_ids.index(resource_id) || resource_ids.length
    projected_at = Time.utc(2026, 8, 30, 12, 2) - index.seconds
    create(
      :coordinator_read_resource,
      resource_id:,
      repository_id:,
      normalized_path: path,
      created_at: projected_at,
      updated_at: projected_at
    )
  end

  def create_work_intention(attempt_id, resource_id, intention_id, agent_id, expires_at)
    resource = Coordinator::Read::Resource.find(resource_id)
    create(
      :coordinator_read_attempt_history,
      :with_work_intention_set,
      attempt_id:,
      change_set_id: "CS-graphql-resources",
      work_item_id: "W-#{attempt_id}",
      agent_id:,
      status: "started",
      base_snapshots: [
        { "repository_id" => resource.repository_id, "object_format" => "sha1", "commit_oid" => "a" * 40 }
      ],
      work_intention_set_repository_id: resource.repository_id,
      work_intention_resource_id: resource_id,
      work_intention_resource_path: resource.normalized_path,
      work_intention_id: intention_id,
      work_intention_mode: "shared",
      work_intention_purpose: "Implement #{attempt_id}",
      work_intention_context: "Keep the intent visible to peers",
      work_intention_set_id: SecureRandom.uuid_v7,
      work_intention_set_expires_at_domain: expires_at
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
