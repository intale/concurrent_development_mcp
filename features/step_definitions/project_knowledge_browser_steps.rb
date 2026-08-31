# frozen_string_literal: true

PROJECT_KNOWLEDGE_SKILL_QUERY = <<~GRAPHQL.freeze
  query ProjectKnowledgeSkill($repositoryId: ID!, $name: String!) {
    projectSkill(repositoryId: $repositoryId, name: $name) {
      skill {
        revision
        instructions
        assets { path }
      }
    }
  }
GRAPHQL

PROJECT_KNOWLEDGE_ARTIFACT_QUERY = <<~GRAPHQL.freeze
  query ProjectKnowledgeArtifact($repositoryId: ID!, $parentId: ID!, $childId: ID!) {
    parent: projectArtifact(repositoryId: $repositoryId, artifactId: $parentId, direction: BOTH) {
      artifact { id title }
      relationships { nodes { direction relation displayRelation peerId status } }
    }
    child: projectArtifact(repositoryId: $repositoryId, artifactId: $childId, direction: BOTH) {
      artifact { id title }
      relationships { nodes { direction relation displayRelation peerId status } }
    }
  }
GRAPHQL

Given("projected knowledge rows contain current and obsolete revisions of one Skill") do
  create_knowledge_browser_project
  skill = FactoryBot.create(
    :coordinator_read_skill,
    skill_id: knowledge_browser_skill_id,
    name: "event-modeling",
    scope: @knowledge_browser_scope,
    revision: 2
  )
  FactoryBot.create(
    :coordinator_read_skill_revision,
    skill:,
    revision: 1,
    instructions: "Obsolete instructions",
    published_global_position: 2_001
  )
  FactoryBot.create(
    :coordinator_read_skill_revision,
    skill:,
    revision: 2,
    instructions: "Current instructions",
    asset_count: 2,
    published_global_position: 2_002
  )
  FactoryBot.create(
    :coordinator_read_skill_asset,
    skill:,
    revision: 1,
    path: "references/obsolete.md"
  )
  FactoryBot.create(
    :coordinator_read_skill_asset,
    skill:,
    revision: 2,
    path: "references/current.md"
  )
  FactoryBot.create(
    :coordinator_read_skill_asset,
    :binary,
    skill:,
    revision: 2,
    path: "assets/template.bin"
  )
end

When("the browser queries the projected project Skill") do
  @knowledge_browser_payload = query_project_knowledge(
    PROJECT_KNOWLEDGE_SKILL_QUERY,
    repositoryId: @knowledge_browser_repository_id,
    name: "event-modeling"
  )
end

Then("only the current Skill instructions and assets are presented") do
  skill = knowledge_browser_data.fetch("projectSkill").fetch("skill")

  assert_acceptance_equal(2, skill.fetch("revision"), "Current Skill revision")
  assert_acceptance_equal("Current instructions", skill.fetch("instructions"), "Current instructions")
  assert_acceptance_equal(
    %w[assets/template.bin references/current.md],
    skill.fetch("assets").map { _1.fetch("path") },
    "Current asset manifest"
  )
end

Given("projected knowledge rows contain related parent and child artifacts with a superseded edge") do
  create_knowledge_browser_project
  create_knowledge_browser_artifact(knowledge_browser_parent_id, "Parent README", "README.md", 2_101)
  create_knowledge_browser_artifact(knowledge_browser_child_id, "Child guide", "docs/guide.md", 2_102)
  create_knowledge_browser_relation("contains", 2_201)
  superseded = create_knowledge_browser_relation("references", 2_202)
  FactoryBot.create(
    :coordinator_read_development_artifact_relation_supersession,
    relation: superseded,
    source_artifact_id: knowledge_browser_parent_id,
    superseded_global_position: 2_203
  )
end

When("the browser queries both projected artifacts") do
  @knowledge_browser_payload = query_project_knowledge(
    PROJECT_KNOWLEDGE_ARTIFACT_QUERY,
    repositoryId: @knowledge_browser_repository_id,
    parentId: knowledge_browser_parent_id,
    childId: knowledge_browser_child_id
  )
end

Then("the parent and child are mutually navigable without the superseded edge") do
  parent = knowledge_browser_data.fetch("parent")
  child = knowledge_browser_data.fetch("child")

  assert_acceptance_equal(
    [ [ "OUTGOING", "CONTAINS", knowledge_browser_child_id ] ],
    parent.dig("relationships", "nodes").map { [ _1.fetch("direction"), _1.fetch("relation"), _1.fetch("peerId") ] },
    "Parent relationships"
  )
  assert_acceptance_equal(
    [ [ "INCOMING", "contained_by", knowledge_browser_parent_id ] ],
    child.dig("relationships", "nodes").map do
      [ _1.fetch("direction"), _1.fetch("displayRelation"), _1.fetch("peerId") ]
    end,
    "Child relationships"
  )
end

def create_knowledge_browser_project
  @knowledge_browser_repository_id ||= SecureRandom.uuid_v7
  @knowledge_browser_scope ||= "project:test/knowledge-browser-#{@knowledge_browser_repository_id}"
  return if Coordinator::Read::Repository.exists?(repository_id: @knowledge_browser_repository_id)

  FactoryBot.create(
    :coordinator_read_repository,
    repository_id: @knowledge_browser_repository_id,
    repository_key: "knowledge-browser-#{@knowledge_browser_repository_id}",
    scope: @knowledge_browser_scope,
    display_name: "Knowledge browser"
  )
end

def create_knowledge_browser_artifact(identifier, title, locator, position)
  artifact = FactoryBot.create(
    :coordinator_read_development_artifact,
    artifact_id: identifier,
    scope: @knowledge_browser_scope,
    title:,
    source_locator: locator,
    content_text: "# #{title}",
    captured_global_position: position
  )
  FactoryBot.create(
    :coordinator_read_development_artifact_observation,
    artifact:,
    observation_id: "artifact-observation:v1:#{identifier.delete_prefix('artifact:v1:')}",
    scope: @knowledge_browser_scope,
    title:,
    source_locator: locator,
    observed_global_position: position,
    classified_global_position: position,
    current_global_position: position
  )
end

def create_knowledge_browser_relation(relation, position)
  FactoryBot.create(
    :coordinator_read_development_artifact_relation,
    source_artifact: Coordinator::Read::DevelopmentArtifact.find(knowledge_browser_parent_id),
    relation_id: "artifact-relation:v1:#{format('%064x', position)}",
    relation:,
    target_id: knowledge_browser_child_id,
    declared_global_position: position
  )
end

def query_project_knowledge(query, variables)
  session = ActionDispatch::Integration::Session.new(Rails.application)
  session.host! "localhost"
  session.post("/graphql", params: { query:, variables: }, as: :json)
  assert_acceptance(session.response.status == 200, "Knowledge GraphQL returned HTTP #{session.response.status}")
  JSON.parse(session.response.body)
end

def knowledge_browser_data
  errors = @knowledge_browser_payload.fetch("errors", [])
  assert_acceptance(errors.empty?, "Knowledge GraphQL failed: #{errors.inspect}")
  @knowledge_browser_payload.fetch("data")
end

def knowledge_browser_skill_id
  "skill:v1:#{'8' * 64}"
end

def knowledge_browser_parent_id
  "artifact:v1:#{'8' * 64}"
end

def knowledge_browser_child_id
  "artifact:v1:#{'9' * 64}"
end
