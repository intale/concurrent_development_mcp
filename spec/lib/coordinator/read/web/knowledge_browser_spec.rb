# frozen_string_literal: true

RSpec.describe Coordinator::Read::Web::Queries::KnowledgeBrowser, :read_model do
  let(:repository_id) { "018f0f4d-4e45-7abc-8def-000000000071" }
  let(:scope) { "project:knowledge-browser" }
  let(:project_ref) { Coordinator::Read::Web::ProjectReference.new.encode(scope:) }
  let(:skill_id) { "018f0f4d-4e45-7abc-8def-000000000111" }
  let(:parent_id) { artifact_id("a") }
  let(:child_id) { artifact_id("b") }

  before do
    create(
      :coordinator_read_repository,
      repository_id:,
      repository_key: "knowledge-browser",
      scope:,
      display_name: "Knowledge browser"
    )
    create(
      :coordinator_read_repository,
      repository_id: "018f0f4d-4e45-7abc-8def-000000000072",
      repository_key: "knowledge-browser-docs",
      scope:,
      display_name: "Knowledge browser docs"
    )
    skill = create(:coordinator_read_skill, skill_id:, name: "event-modeling", scope:, revision: 2)
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
    create(
      :coordinator_read_skill_asset,
      skill:,
      revision: 1,
      path: "references/obsolete.md",
      content_text: "obsolete"
    )
    create(
      :coordinator_read_skill_asset,
      skill:,
      revision: 2,
      path: "references/current.md",
      content_text: "current reference"
    )
    create(:coordinator_read_skill_asset, :binary, skill:, revision: 2, path: "assets/template.bin")
    other = create(:coordinator_read_skill, name: "event-modeling", scope: "project:other")
    create(:coordinator_read_skill_revision, skill: other)

    create_artifact(parent_id, "Parent README", "README.md", 801)
    create_artifact(child_id, "Child guide", "docs/guide.md", 802)
    create_relation(parent_id, child_id, "contains", 1_001)
    superseded = create_relation(parent_id, child_id, "references", 1_002)
    create(
      :coordinator_read_development_artifact_relation_supersession,
      relation: superseded,
      source_artifact_id: parent_id,
      superseded_global_position: 1_003
    )
  end

  it "serves separate bounded Skill and Artifact collections for the exact Project scope" do
    skills = query.skills(project_ref:, first: 1)
    artifacts = query.artifacts(project_ref:, first: 1)

    expect(skills.items.map(&:skill_id)).to eq([ skill_id ])
    expect(skills.items.first).to have_attributes(revision: 2, asset_count: 2)
    expect(artifacts.items.map(&:artifact_id)).to eq([ parent_id ])
    expect(artifacts).to have_attributes(has_more: true, next_global_position: 801)

    second = query.artifacts(
      project_ref:,
      first: 1,
      after_global_position: artifacts.next_global_position
    )
    expect(second.items.map(&:artifact_id)).to eq([ child_id ])
  end

  it "returns only the latest Skill revision and its current text or binary assets" do
    detail = query.skill(project_ref:, name: "event-modeling")
    text = query.skill_asset(project_ref:, name: "event-modeling", path: "references/current.md")
    binary = query.skill_asset(project_ref:, name: "event-modeling", path: "assets/template.bin")

    expect(detail.skill).to have_attributes(revision: 2, instructions: "Current instructions")
    expect(detail.skill.assets.map(&:path)).to contain_exactly(
      "assets/template.bin",
      "references/current.md"
    )
    expect(text.asset).to have_attributes(revision: 2, text: "current reference")
    expect(binary.asset).to have_attributes(revision: 2, base64: "ZmFjdG9yeQ==")
    expect(query.skill_asset(
      project_ref:,
      name: "event-modeling",
      path: "references/obsolete.md"
    )).to be_nil
  end

  it "separates Artifact content from active relationship traversal" do
    parent = query.artifact(project_ref:, artifact_id: parent_id)
    parent_relationships = query.relationships(project_ref:, artifact_id: parent_id, first: 20)
    child_relationships = query.relationships(project_ref:, artifact_id: child_id, first: 20)

    expect(parent.artifact).to have_attributes(
      observation_id: observation_id("a"),
      title: "Parent README",
      scope:
    )
    expect(parent.content).to have_attributes(text: "# Parent README")
    expect(parent_relationships.relationships.items.map { [ _1.direction, _1.relation, _1.peer_id ] }).to eq(
      [ [ "outgoing", "contains", child_id ] ]
    )
    expect(child_relationships.relationships.items.map { [ _1.direction, _1.display_relation, _1.peer_id ] }).to eq(
      [ [ "incoming", "contained_by", parent_id ] ]
    )
  end

  it "rejects malformed input and isolates Project-scoped details" do
    expect do
      query.skills(project_ref: "invalid")
    end.to raise_error(Coordinator::Read::Web::ProjectReference::InvalidReference)
    expect do
      query.artifacts(project_ref:, labels: [ " padded" ])
    end.to raise_error(Coordinator::Read::Web::KnowledgeBrowserQueryError)
    expect do
      query.relationships(
        project_ref:,
        artifact_id: parent_id,
        cursor: {
          after_observed_sequence: 2,
          through_observed_sequence: 1,
          after_declared_global_position: nil,
          after_relation_id: nil
        }
      )
    end.to raise_error(Coordinator::Read::Web::KnowledgeBrowserQueryError)

    outside = create_artifact(artifact_id("c"), "Outside", "outside.md", 803, artifact_scope: "project:other")
    expect(query.artifact(project_ref:, artifact_id: outside.artifact_id)).to be_nil
  end

  def query
    described_class.new
  end

  def artifact_id(hex)
    format("018f0f52-4e45-7abc-8def-%012x", hex.to_i(16))
  end

  def observation_id(hex)
    format("018f0f53-4e45-7abc-8def-%012x", hex.to_i(16))
  end

  def create_artifact(identifier, title, locator, position, artifact_scope: scope)
    artifact = create(
      :coordinator_read_development_artifact,
      artifact_id: identifier,
      scope: artifact_scope,
      title:,
      source_locator: locator,
      content_text: "# #{title}",
      captured_global_position: position
    )
    create(
      :coordinator_read_development_artifact_observation,
      artifact:,
      observation_id: observation_id(identifier[-1]),
      scope: artifact_scope,
      title:,
      source_locator: locator,
      observed_global_position: position,
      classified_global_position: position,
      current_global_position: position
    )
    artifact
  end

  def create_relation(source_id, target_id, relation, position)
    source = Coordinator::Read::DevelopmentArtifact.find(source_id)
    create(
      :coordinator_read_development_artifact_relation,
      source_artifact: source,
      relation_id: format("018f0f54-4e45-7abc-8def-%012x", position),
      relation:,
      target_id:,
      declared_global_position: position
    )
  end
end
