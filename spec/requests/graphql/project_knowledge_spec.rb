# frozen_string_literal: true

module ProjectKnowledgeGraphqlSpec
  RSpec.describe "GraphQL project knowledge", :read_model do
    SKILLS_QUERY = <<~GRAPHQL.freeze
      query ProjectSkills($projectRef: ID!, $first: Int, $name: String, $after: String) {
        projectSkills(projectRef: $projectRef, first: $first, name: $name, after: $after) {
          nodes { id name scope revision description assetCount contentDigest publishedAt }
          pageInfo { endCursor hasNextPage }
        }
      }
    GRAPHQL

    ARTIFACTS_QUERY = <<~GRAPHQL.freeze
      query ProjectArtifacts(
        $projectRef: ID!
        $first: Int
        $kind: DevelopmentArtifactKind
        $labels: [String!]
        $sourceKind: DevelopmentArtifactSourceKind
        $after: String
      ) {
        projectArtifacts(
          projectRef: $projectRef
          first: $first
          kind: $kind
          labels: $labels
          sourceKind: $sourceKind
          after: $after
        ) {
          nodes {
            id observationId scope title kind labels mediaType encoding contentDigest byteSize
            classificationRevision classificationReason relationshipCount
            capturedAt observedAt classifiedAt
            source { kind locator revision observedAt collector }
          }
          pageInfo { endCursor hasNextPage }
        }
      }
    GRAPHQL

    SKILL_QUERY = <<~GRAPHQL.freeze
      query ProjectSkill($projectRef: ID!, $name: String!) {
        projectSkill(projectRef: $projectRef, name: $name) {
          skill {
            id name scope revision description instructions contentDigest publishedAt
            assets { path mediaType executable contentDigest byteSize }
          }
        }
      }
    GRAPHQL

    SKILL_ASSET_QUERY = <<~GRAPHQL.freeze
      query ProjectSkillAsset($projectRef: ID!, $name: String!, $path: String!) {
        projectSkillAsset(projectRef: $projectRef, name: $name, path: $path) {
          asset { path revision encoding mediaType executable text base64 contentDigest byteSize }
        }
      }
    GRAPHQL

    ARTIFACT_QUERY = <<~GRAPHQL.freeze
      query ProjectArtifact($projectRef: ID!, $artifactId: ID!) {
        projectArtifact(projectRef: $projectRef, artifactId: $artifactId) {
          artifact { id observationId scope title kind labels source { kind locator } }
          content { encoding mediaType text base64 contentDigest byteSize }
        }
      }
    GRAPHQL

    RELATIONSHIPS_QUERY = <<~GRAPHQL.freeze
      query ProjectArtifactRelationships(
        $projectRef: ID!
        $artifactId: ID!
        $first: Int
        $direction: ArtifactRelationDirection
        $relation: DevelopmentArtifactRelationKind
        $after: String
      ) {
        projectArtifactRelationships(
          projectRef: $projectRef
          artifactId: $artifactId
          first: $first
          direction: $direction
          relation: $relation
          after: $after
        ) {
          artifact { id title source { locator } }
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
    MEMBER_REPOSITORY_ID = "018f0f4d-4e45-7abc-8def-000000000083"
    OTHER_REPOSITORY_ID = "018f0f4d-4e45-7abc-8def-000000000082"
    SCOPE = "project:graphql-knowledge"
    OTHER_SCOPE = "project:other-knowledge"
    SKILL_ID = "skill:v1:#{'1' * 64}"
    PARENT_ID = "artifact:v1:#{'a' * 64}"
    CHILD_ID = "artifact:v1:#{'b' * 64}"

    before do
      create_project(REPOSITORY_ID, SCOPE, "GraphQL knowledge")
      create_project(MEMBER_REPOSITORY_ID, SCOPE, "GraphQL knowledge docs")
      create_project(OTHER_REPOSITORY_ID, OTHER_SCOPE, "Other knowledge")
      create_skill
      create_artifacts
    end

    it "serves separate current Skill and Artifact collections for the exact Project scope" do
      skills = execute(
        SKILLS_QUERY,
        projectRef: project_ref,
        first: 20,
        name: "event-modeling"
      ).dig("data", "projectSkills")
      artifacts = execute(
        ARTIFACTS_QUERY,
        projectRef: project_ref,
        first: 20,
        kind: "DOCUMENTATION",
        labels: [ "docs" ],
        sourceKind: "LOCAL_FILE"
      ).dig("data", "projectArtifacts")

      expect(skills.dig("nodes", 0)).to include(
        "id" => SKILL_ID,
        "name" => "event-modeling",
        "scope" => SCOPE,
        "revision" => 2,
        "assetCount" => 2
      )
      expect(artifacts.fetch("nodes").map { _1.fetch("id") }).to eq([ PARENT_ID, CHILD_ID ])
      expect(artifacts.dig("nodes", 0)).to include("kind" => "DOCUMENTATION", "labels" => %w[docs root])
      expect(artifacts.dig("nodes", 0, "source")).to include("kind" => "LOCAL_FILE", "locator" => "README.md")
    end

    it "returns only the current Skill revision and its current text or binary assets" do
      skill = execute(SKILL_QUERY, projectRef: project_ref, name: "event-modeling")
        .dig("data", "projectSkill", "skill")
      text = execute(
        SKILL_ASSET_QUERY,
        projectRef: project_ref,
        name: "event-modeling",
        path: "references/current.md"
      ).dig("data", "projectSkillAsset", "asset")
      binary = execute(
        SKILL_ASSET_QUERY,
        projectRef: project_ref,
        name: "event-modeling",
        path: "assets/template.bin"
      ).dig("data", "projectSkillAsset", "asset")
      obsolete = execute(
        SKILL_ASSET_QUERY,
        projectRef: project_ref,
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

    it "separates Artifact content from active relationship navigation" do
      parent = execute(ARTIFACT_QUERY, projectRef: project_ref, artifactId: PARENT_ID)
        .dig("data", "projectArtifact")
      parent_edges = relationships(PARENT_ID)
      child_edges = relationships(CHILD_ID)

      expect(parent.fetch("content")).to include("encoding" => "utf-8", "text" => "# Parent README")
      expect(parent_edges.dig("relationships", "nodes").sole).to include(
        "direction" => "OUTGOING",
        "relation" => "CONTAINS",
        "peerId" => CHILD_ID,
        "status" => "active"
      )
      expect(parent_edges.dig("relationships", "nodes", 0, "peerArtifact")).to include(
        "id" => CHILD_ID,
        "title" => "Child guide"
      )
      expect(child_edges.dig("relationships", "nodes").sole).to include(
        "direction" => "INCOMING",
        "displayRelation" => "contained_by",
        "peerId" => PARENT_ID
      )
    end

    it "uses opaque filter-bound cursors and rejects malformed or cross-Project input" do
      first = execute(ARTIFACTS_QUERY, projectRef: project_ref, first: 1)
        .dig("data", "projectArtifacts")
      cursor = first.dig("pageInfo", "endCursor")

      expect(first.dig("nodes", 0, "id")).to eq(PARENT_ID)
      expect(first.dig("pageInfo", "hasNextPage")).to be(true)
      expect(cursor).not_to include("801")
      expect(
        execute(ARTIFACTS_QUERY, projectRef: project_ref, first: 1, after: cursor)
          .dig("data", "projectArtifacts", "nodes", 0, "id")
      ).to eq(CHILD_ID)

      mismatched = execute(
        ARTIFACTS_QUERY,
        projectRef: project_ref,
        first: 1,
        kind: "DOCUMENTATION",
        after: cursor
      )
      malformed = execute(SKILLS_QUERY, projectRef: "not-a-project-ref", first: 20)
      outside = execute(ARTIFACT_QUERY, projectRef: other_project_ref, artifactId: PARENT_ID)

      expect(mismatched.dig("errors", 0, "extensions", "code")).to eq("INVALID_CURSOR")
      expect(malformed.dig("errors", 0, "extensions", "code")).to eq("INVALID_PROJECT_REFERENCE")
      expect(outside.dig("data", "projectArtifact")).to be_nil
    end

    def relationships(artifact_id)
      execute(
        RELATIONSHIPS_QUERY,
        projectRef: project_ref,
        artifactId: artifact_id,
        first: 20,
        direction: "BOTH"
      ).dig("data", "projectArtifactRelationships")
    end

    def project_ref
      Coordinator::Read::Web::ProjectReference.new.encode(scope: SCOPE)
    end

    def other_project_ref
      Coordinator::Read::Web::ProjectReference.new.encode(scope: OTHER_SCOPE)
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

      other = create(:coordinator_read_skill, name: "event-modeling", scope: OTHER_SCOPE)
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
