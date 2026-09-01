# frozen_string_literal: true

module ProjectKnowledgeGraphqlSpec
  RSpec.describe "GraphQL project knowledge", :read_model do
  CATALOG_QUERY = <<~GRAPHQL.freeze
    query ProjectKnowledge(
      $repositoryId: ID!
      $first: Int
      $skillName: String
      $skillsAfter: String
      $artifactKind: DevelopmentArtifactKind
      $artifactLabels: [String!]
      $artifactSourceKind: DevelopmentArtifactSourceKind
      $artifactsAfter: String
    ) {
      projectKnowledge(
        repositoryId: $repositoryId
        first: $first
        skillName: $skillName
        skillsAfter: $skillsAfter
        artifactKind: $artifactKind
        artifactLabels: $artifactLabels
        artifactSourceKind: $artifactSourceKind
        artifactsAfter: $artifactsAfter
      ) {
        project { id name scope }
        skills {
          nodes { id name scope revision description assetCount contentDigest publishedAt }
          pageInfo { endCursor hasNextPage }
        }
        artifacts {
          nodes {
            id observationId scope title kind labels mediaType encoding contentDigest byteSize
            classificationRevision classificationReason relationshipCount
            capturedAt observedAt classifiedAt
            source { kind locator revision observedAt collector }
          }
          pageInfo { endCursor hasNextPage }
        }
      }
    }
  GRAPHQL

  SKILL_QUERY = <<~GRAPHQL.freeze
    query ProjectSkill($repositoryId: ID!, $name: String!) {
      projectSkill(repositoryId: $repositoryId, name: $name) {
        project { id scope }
        skill {
          id name scope revision description instructions contentDigest publishedAt
          assets { path mediaType executable contentDigest byteSize }
        }
      }
    }
  GRAPHQL

  SKILL_ASSET_QUERY = <<~GRAPHQL.freeze
    query ProjectSkillAsset($repositoryId: ID!, $name: String!, $path: String!) {
      projectSkillAsset(repositoryId: $repositoryId, name: $name, path: $path) {
        project { id scope }
        asset { path revision encoding mediaType executable text base64 contentDigest byteSize }
      }
    }
  GRAPHQL

  ARTIFACT_QUERY = <<~GRAPHQL.freeze
    query ProjectArtifact(
      $repositoryId: ID!
      $artifactId: ID!
      $first: Int
      $direction: ArtifactRelationDirection
      $relation: DevelopmentArtifactRelationKind
      $relationsAfter: String
    ) {
      projectArtifact(
        repositoryId: $repositoryId
        artifactId: $artifactId
        first: $first
        direction: $direction
        relation: $relation
        relationsAfter: $relationsAfter
      ) {
        project { id scope }
        artifact { id observationId scope title kind labels source { kind locator } }
        content { encoding mediaType text base64 contentDigest byteSize }
        relationships {
          nodes {
            id direction relation displayRelation peerKind peerId status
            targetStatus targetName targetScope path fragment normalizedLocator declaredAt
            peerArtifact { id title kind source { locator } }
          }
          pageInfo { endCursor hasNextPage }
        }
      }
    }
  GRAPHQL

  REPOSITORY_ID = "018f0f4d-4e45-7abc-8def-000000000081"
  OTHER_REPOSITORY_ID = "018f0f4d-4e45-7abc-8def-000000000082"
  SCOPE = "project:graphql-knowledge"
  SKILL_ID = "skill:v1:#{'1' * 64}"
  PARENT_ID = "artifact:v1:#{'a' * 64}"
  CHILD_ID = "artifact:v1:#{'b' * 64}"

  before do
    create_project(REPOSITORY_ID, SCOPE, "GraphQL knowledge")
    create_project(OTHER_REPOSITORY_ID, "project:other-knowledge", "Other knowledge")
    create_skill
    create_artifacts
  end

  it "serves current Skill and Artifact summaries from the exact project scope" do
    result = execute(
      CATALOG_QUERY,
      repositoryId: REPOSITORY_ID,
      first: 20,
      skillName: "event-modeling",
      artifactKind: "DOCUMENTATION",
      artifactLabels: [ "docs" ],
      artifactSourceKind: "LOCAL_FILE"
    ).dig("data", "projectKnowledge")

    expect(result.fetch("project")).to include("id" => REPOSITORY_ID, "scope" => SCOPE)
    expect(result.dig("skills", "nodes").sole).to include(
      "id" => SKILL_ID,
      "name" => "event-modeling",
      "scope" => SCOPE,
      "revision" => 2,
      "assetCount" => 2
    )
    expect(result.dig("artifacts", "nodes").map { _1.fetch("id") }).to eq([ PARENT_ID, CHILD_ID ])
    expect(result.dig("artifacts", "nodes", 0)).to include(
      "kind" => "DOCUMENTATION",
      "labels" => %w[docs root]
    )
    expect(result.dig("artifacts", "nodes", 0, "source")).to include(
      "kind" => "LOCAL_FILE",
      "locator" => "README.md"
    )
  end

  it "returns only the current Skill revision and its current text or binary assets" do
    skill = execute(SKILL_QUERY, repositoryId: REPOSITORY_ID, name: "event-modeling")
      .dig("data", "projectSkill", "skill")
    text = execute(
      SKILL_ASSET_QUERY,
      repositoryId: REPOSITORY_ID,
      name: "event-modeling",
      path: "references/current.md"
    ).dig("data", "projectSkillAsset", "asset")
    binary = execute(
      SKILL_ASSET_QUERY,
      repositoryId: REPOSITORY_ID,
      name: "event-modeling",
      path: "assets/template.bin"
    ).dig("data", "projectSkillAsset", "asset")
    obsolete = execute(
      SKILL_ASSET_QUERY,
      repositoryId: REPOSITORY_ID,
      name: "event-modeling",
      path: "references/obsolete.md"
    )

    expect(skill).to include("revision" => 2, "instructions" => "Current instructions")
    expect(skill.fetch("assets").map { _1.fetch("path") }).to eq(
      %w[assets/template.bin references/current.md]
    )
    expect(text).to include("revision" => 2, "encoding" => "utf-8", "text" => "current reference")
    expect(binary).to include("revision" => 2, "encoding" => "binary", "base64" => "ZmFjdG9yeQ==")
    expect(obsolete.dig("data", "projectSkillAsset")).to be_nil
  end

  it "navigates active parent and child relationships in both directions" do
    parent = execute(
      ARTIFACT_QUERY,
      repositoryId: REPOSITORY_ID,
      artifactId: PARENT_ID,
      first: 20,
      direction: "BOTH"
    ).dig("data", "projectArtifact")
    child = execute(
      ARTIFACT_QUERY,
      repositoryId: REPOSITORY_ID,
      artifactId: CHILD_ID,
      first: 20,
      direction: "BOTH"
    ).dig("data", "projectArtifact")

    expect(parent.fetch("content")).to include("encoding" => "utf-8", "text" => "# Parent README")
    expect(parent.dig("relationships", "nodes").sole).to include(
      "direction" => "OUTGOING",
      "relation" => "CONTAINS",
      "peerId" => CHILD_ID,
      "status" => "active"
    )
    expect(parent.dig("relationships", "nodes", 0, "peerArtifact")).to include(
      "id" => CHILD_ID,
      "title" => "Child guide"
    )
    expect(child.dig("relationships", "nodes").sole).to include(
      "direction" => "INCOMING",
      "displayRelation" => "contained_by",
      "peerId" => PARENT_ID
    )
  end

  it "uses opaque filter-bound cursors and rejects malformed or cross-project input" do
    first = execute(CATALOG_QUERY, repositoryId: REPOSITORY_ID, first: 1)
      .dig("data", "projectKnowledge", "artifacts")
    cursor = first.dig("pageInfo", "endCursor")

    expect(first.dig("nodes", 0, "id")).to eq(PARENT_ID)
    expect(first.dig("pageInfo", "hasNextPage")).to be(true)
    expect(cursor).not_to include("801")
    expect(
      execute(CATALOG_QUERY, repositoryId: REPOSITORY_ID, first: 1, artifactsAfter: cursor)
        .dig("data", "projectKnowledge", "artifacts", "nodes", 0, "id")
    ).to eq(CHILD_ID)

    mismatched = execute(
      CATALOG_QUERY,
      repositoryId: REPOSITORY_ID,
      first: 1,
      artifactKind: "DOCUMENTATION",
      artifactsAfter: cursor
    )
    malformed = execute(CATALOG_QUERY, repositoryId: "not-a-uuid", first: 20)
    outside = execute(
      ARTIFACT_QUERY,
      repositoryId: OTHER_REPOSITORY_ID,
      artifactId: PARENT_ID,
      first: 20,
      direction: "BOTH"
    )

    expect(mismatched.dig("errors", 0, "extensions", "code")).to eq("INVALID_CURSOR")
    expect(malformed.dig("errors", 0, "extensions", "code")).to eq("INVALID_INPUT")
    expect(outside.dig("data", "projectArtifact")).to be_nil
  end

  def create_project(repository_id, scope, name)
    create(
      :coordinator_read_repository,
      repository_id:,
      repository_key: "knowledge-#{repository_id}",
      scope:,
      display_name: name
    )
  end

  def create_skill
    skill = create(:coordinator_read_skill, skill_id: SKILL_ID, name: "event-modeling", scope: SCOPE, revision: 2)
    create(
      :coordinator_read_skill_revision,
      skill:,
      revision: 1,
      instructions: "Obsolete instructions",
      published_global_position: 501
    )
    create(
      :coordinator_read_skill_revision,
      skill:,
      revision: 2,
      instructions: "Current instructions",
      asset_count: 2,
      published_global_position: 502
    )
    create(:coordinator_read_skill_asset, skill:, revision: 1, path: "references/obsolete.md")
    create(
      :coordinator_read_skill_asset,
      skill:,
      revision: 2,
      path: "references/current.md",
      content_text: "current reference"
    )
    create(:coordinator_read_skill_asset, :binary, skill:, revision: 2, path: "assets/template.bin")

    other = create(:coordinator_read_skill, name: "event-modeling", scope: "project:other-knowledge")
    create(:coordinator_read_skill_revision, skill: other)
  end

  def create_artifacts
    create_artifact(PARENT_ID, "Parent README", "README.md", 801, %w[docs root])
    create_artifact(CHILD_ID, "Child guide", "docs/guide.md", 802, %w[docs guide])
    create_relation("contains", 1_001)
    superseded = create_relation("references", 1_002)
    create(
      :coordinator_read_development_artifact_relation_supersession,
      relation: superseded,
      source_artifact_id: PARENT_ID,
      superseded_global_position: 1_003
    )
  end

  def create_artifact(identifier, title, locator, position, labels)
    artifact = create(
      :coordinator_read_development_artifact,
      artifact_id: identifier,
      scope: SCOPE,
      title:,
      labels:,
      source_locator: locator,
      content_text: "# #{title}",
      captured_global_position: position
    )
    create(
      :coordinator_read_development_artifact_observation,
      artifact:,
      observation_id: "artifact-observation:v1:#{identifier.delete_prefix('artifact:v1:')}",
      scope: SCOPE,
      title:,
      labels:,
      source_locator: locator,
      observed_global_position: position,
      classified_global_position: position,
      current_global_position: position
    )
  end

  def create_relation(relation, position)
    create(
      :coordinator_read_development_artifact_relation,
      source_artifact: Coordinator::Read::DevelopmentArtifact.find(PARENT_ID),
      relation_id: "artifact-relation:v1:#{format('%064x', position)}",
      relation:,
      target_id: CHILD_ID,
      declared_global_position: position
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
end
