# frozen_string_literal: true

PROJECT_KNOWLEDGE_SKILL_QUERY = <<~GRAPHQL.freeze
  query ProjectKnowledgeSkill($projectRef: ID!, $name: String!) {
    projectSkill(projectRef: $projectRef, name: $name) {
      skill {
        revision
        instructions
        assets { path }
      }
    }
  }
GRAPHQL

PROJECT_KNOWLEDGE_ARTIFACT_QUERY = <<~GRAPHQL.freeze
  query ProjectKnowledgeArtifact($projectRef: ID!, $parentId: ID!, $childId: ID!) {
    parent: projectArtifactRelationships(projectRef: $projectRef, artifactId: $parentId, direction: BOTH) {
      artifact { id title }
      relationships { nodes { direction relation displayRelation peerId status } }
    }
    child: projectArtifactRelationships(projectRef: $projectRef, artifactId: $childId, direction: BOTH) {
      artifact { id title }
      relationships { nodes { direction relation displayRelation peerId status } }
    }
  }
GRAPHQL

GLOBAL_KNOWLEDGE_SKILLS_QUERY = <<~GRAPHQL.freeze
  query GlobalKnowledgeSkills($projectScope: String, $name: String) {
    skills(projectScope: $projectScope, name: $name, first: 20) {
      nodes { id name scope }
    }
  }
GRAPHQL

GLOBAL_KNOWLEDGE_SKILL_QUERY = <<~GRAPHQL.freeze
  query GlobalKnowledgeSkill($skillId: ID!) {
    skill(skillId: $skillId) {
      skill { id name scope instructions }
    }
  }
GRAPHQL

Given("projected global Skills contain the same name in two Project scopes") do
  create_knowledge_browser_project
  selected = FactoryBot.create(
    :coordinator_read_skill,
    skill_id: knowledge_browser_skill_id,
    name: "event-modeling",
    scope: @knowledge_browser_scope
  )
  FactoryBot.create(
    :coordinator_read_skill_revision,
    skill: selected,
    instructions: "Selected Project instructions"
  )

  other_scope = "project:test/knowledge-browser-other-#{SecureRandom.uuid_v7}"
  FactoryBot.create(:coordinator_read_repository, scope: other_scope)
  other = FactoryBot.create(:coordinator_read_skill, name: "event-modeling", scope: other_scope)
  FactoryBot.create(:coordinator_read_skill_revision, skill: other, instructions: "Other Project instructions")
end

When("the browser filters global Skills by the exact selected Project and name") do
  @global_knowledge_skills_payload = query_project_knowledge(
    GLOBAL_KNOWLEDGE_SKILLS_QUERY,
    projectScope: @knowledge_browser_scope,
    name: "event-modeling"
  )
end

Then("only the selected scoped Skill is presented and opens by stable identity") do
  rows = @global_knowledge_skills_payload.fetch("data").fetch("skills").fetch("nodes")
  assert_acceptance_equal(
    [ [ knowledge_browser_skill_id, "event-modeling", @knowledge_browser_scope ] ],
    rows.map { _1.values_at("id", "name", "scope") },
    "Exactly scoped global Skills"
  )

  detail = query_project_knowledge(
    GLOBAL_KNOWLEDGE_SKILL_QUERY,
    skillId: rows.sole.fetch("id")
  ).fetch("data").fetch("skill").fetch("skill")
  assert_acceptance_equal(
    [ knowledge_browser_skill_id, "Selected Project instructions" ],
    detail.values_at("id", "instructions"),
    "Stable Skill detail"
  )
end

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

When("the browser opens the focused projected Skill detail") do
  @knowledge_browser_payload = query_project_knowledge(
    PROJECT_KNOWLEDGE_SKILL_QUERY,
    projectRef: @knowledge_browser_project_ref,
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

When("the browser opens the focused relationship views for both projected Artifacts") do
  @knowledge_browser_payload = query_project_knowledge(
    PROJECT_KNOWLEDGE_ARTIFACT_QUERY,
    projectRef: @knowledge_browser_project_ref,
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
  @knowledge_browser_project_ref ||= Coordinator::Read::Web::ProjectReference.new.encode(
    scope: @knowledge_browser_scope
  )
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
    observation_id: identifier == knowledge_browser_parent_id ?
      knowledge_browser_parent_observation_id : knowledge_browser_child_observation_id,
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
    relation_id: format("018f0f50-4e45-7abc-8def-%012x", position),
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
  "018f0f4d-4e45-7abc-8def-000000000088"
end

def knowledge_browser_parent_id
  "018f0f4d-4e45-7abc-8def-000000000089"
end

def knowledge_browser_child_id
  "018f0f4d-4e45-7abc-8def-000000000090"
end

def knowledge_browser_parent_observation_id
  "018f0f4d-4e45-7abc-8def-000000000091"
end

def knowledge_browser_child_observation_id
  "018f0f4d-4e45-7abc-8def-000000000092"
end
