# frozen_string_literal: true

RSpec.describe "Development Artifact queries", :read_model do
  it "serves projected metadata separately from focused content" do
    artifact, observation = create_observed_artifact(
      title: "First",
      content_text: "first document\n",
      content_byte_size: 15,
      source_locator: "docs/first.md"
    )

    get = Coordinator::Read::Queries::DevelopmentArtifactGet.new.call(
      artifact_id: artifact.artifact_id,
      observation_id: observation.observation_id
    ).value!
    content = Coordinator::Read::Queries::DevelopmentArtifactContentGet.new.call(
      artifact_id: artifact.artifact_id,
      observation_id: observation.observation_id
    ).value!

    expect(get).to have_attributes(status: "ok", warnings: [])
    expect(get.data.artifact.artifact).to have_attributes(
      artifact_id: artifact.artifact_id,
      observation_id: observation.observation_id,
      content_sha256: a_string_matching(/\Asha256:/)
    )
    expect(get.to_h.to_s).not_to include("first document")
    expect(content).to have_attributes(status: "ok")
    expect(content.data.content).to have_attributes(
      text: "first document\n",
      media_type: "text/markdown"
    )
    expect(content.data.content.to_h).not_to have_key(:base64)
    expect(content.warnings.sole).to include("passive data")
  end

  it "rejects retired digest-derived identifiers at public read boundaries" do
    artifact_id = "artifact:v1:#{'b' * 64}"
    observation_id = "artifact-observation:v1:#{'c' * 64}"
    get = Coordinator::Read::Queries::DevelopmentArtifactGet.new.call(artifact_id:, observation_id:).value!
    content = Coordinator::Read::Queries::DevelopmentArtifactContentGet.new.call(artifact_id:).value!

    expect(get).to have_attributes(status: "invalid")
    expect(content).to have_attributes(status: "invalid")
    expect(Coordinator::Read::DevelopmentArtifact.count).to eq(0)
  end

  it "reports invalid and unavailable projected artifacts without consulting the write side" do
    invalid = Coordinator::Read::Queries::DevelopmentArtifactGet.new.call(artifact_id: "invalid").value!
    missing_id = "018f0f4d-4e45-7abc-8def-000000000191"
    missing = Coordinator::Read::Queries::DevelopmentArtifactGet.new.call(
      artifact_id: missing_id
    ).value!
    missing_content = Coordinator::Read::Queries::DevelopmentArtifactContentGet.new.call(
      artifact_id: missing_id
    ).value!

    expect(invalid).to have_attributes(status: "invalid")
    expect(invalid.data).to have_attributes(code: "invalid_input")
    expect(missing).to have_attributes(status: "not_found")
    expect(missing.data).to have_attributes(code: "development_artifact_not_observed")
    expect(missing_content).to have_attributes(status: "not_found")
  end

  it "lists in projected order with all-label and exact relation-target filters" do
    first, = create_observed_artifact(
      title: "First",
      labels: %w[docs review],
      source_locator: "first.md",
      current_global_position: 100
    )
    second, = create_observed_artifact(
      title: "Second",
      labels: %w[docs second-only],
      source_locator: "second.md",
      current_global_position: 200
    )
    create_observed_artifact(
      title: "Third",
      kind: "verification_evidence",
      labels: %w[logs],
      source_locator: "third.log",
      current_global_position: 300
    )
    create(
      :coordinator_read_development_artifact_relation,
      source_artifact: second,
      relation: "documents",
      target_kind: "external",
      target_id: "https://example.test/builds/build-1",
      path: "notes/second.md"
    )

    labels = Coordinator::Read::Queries::DevelopmentArtifactList.new.call(
      labels: %w[docs second-only],
      limit: 10
    ).value!
    related = Coordinator::Read::Queries::DevelopmentArtifactList.new.call(
      relation_target: { kind: "external", id: "https://example.test/builds/build-1" },
      limit: 10
    ).value!
    page_one = Coordinator::Read::Queries::DevelopmentArtifactList.new.call(limit: 1).value!
    page_two = Coordinator::Read::Queries::DevelopmentArtifactList.new.call(
      after_global_position: page_one.data.page.next_global_position,
      limit: 10
    ).value!

    expect(labels.data.page.items.map(&:artifact_id)).to eq([ second.artifact_id ])
    expect(related.data.page.items.map(&:artifact_id)).to eq([ second.artifact_id ])
    expect(page_one.data.page).to have_attributes(has_more: true)
    expect(page_one.data.page.items.map(&:artifact_id)).to eq([ first.artifact_id ])
    expect(page_two.data.page.items.map(&:artifact_id)).to include(second.artifact_id)
  end

  it "traverses directed mixed relationships with peer summaries and follow actions" do
    first_parent, = create_observed_artifact(title: "First parent", source_locator: "p1.md")
    second_parent, = create_observed_artifact(title: "Second parent", source_locator: "p2.md")
    child, = create_observed_artifact(title: "Child", source_locator: "child.md")
    first = create(
      :coordinator_read_development_artifact_relation,
      source_artifact: first_parent,
      relation: "references",
      target_id: child.artifact_id,
      path: "child.md",
      normalized_locator: "child.md",
      declared_global_position: 100
    )
    second = create(
      :coordinator_read_development_artifact_relation,
      source_artifact: second_parent,
      relation: "contains",
      target_id: child.artifact_id,
      declared_global_position: 200
    )

    incoming = relation_query.call(
      artifact_id: child.artifact_id,
      direction: "incoming",
      limit: 10
    ).value!.data.page
    filtered = relation_query.call(
      artifact_id: child.artifact_id,
      direction: "incoming",
      relation: "references",
      limit: 10
    ).value!.data.page
    outgoing = relation_query.call(
      artifact_id: first_parent.artifact_id,
      direction: "outgoing",
      limit: 10
    ).value!.data.page

    expect(incoming.items.map(&:relation_id)).to contain_exactly(first.relation_id, second.relation_id)
    expect(incoming.items).to all(have_attributes(direction: "incoming", peer_kind: "artifact"))
    expect(incoming.items.map { _1.peer_artifact.artifact_id }).to contain_exactly(
      first_parent.artifact_id,
      second_parent.artifact_id
    )
    expect(filtered.items.sole).to have_attributes(
      relation: "references",
      display_relation: "referenced_by",
      inverse_relation: "referenced_by",
      transitive: false,
      supersedable: true,
      follow_action: have_attributes(
        tool: "development_artifact_get",
        arguments: have_attributes(artifact_id: first_parent.artifact_id)
      )
    )
    expect(outgoing.items.sole).to have_attributes(
      direction: "outgoing",
      peer_id: child.artifact_id,
      peer_artifact: have_attributes(artifact_id: child.artifact_id),
      relation_attributes: have_attributes(path: "child.md", normalized_locator: "child.md"),
      display_relation: "references",
      target: have_attributes(status: "verified"),
      follow_action: have_attributes(
        tool: "development_artifact_get",
        arguments: have_attributes(artifact_id: child.artifact_id)
      )
    )
  end

  it "continues relation snapshots and then observes rows added after the fixed window" do
    parent, = create_observed_artifact(title: "Parent", source_locator: "parent.md")
    children = 3.times.map do |index|
      create_observed_artifact(
        title: "Child #{index + 1}",
        source_locator: "child-#{index + 1}.md"
      ).first
    end
    first = create_relation(parent:, child: children.fetch(0), global_position: 100)
    second = create_relation(parent:, child: children.fetch(1), global_position: 200)

    first_page = relation_query.call(
      artifact_id: parent.artifact_id,
      direction: "outgoing",
      limit: 1
    ).value!.data.page
    third = create_relation(parent:, child: children.fetch(2), global_position: 50)
    second_page = relation_query.call(
      artifact_id: parent.artifact_id,
      direction: "outgoing",
      cursor: first_page.continuation_cursor.to_h,
      limit: 1
    ).value!.data.page
    later_page = relation_query.call(
      artifact_id: parent.artifact_id,
      direction: "outgoing",
      cursor: second_page.continuation_cursor.to_h,
      limit: 10
    ).value!.data.page

    expect(first_page.items.map(&:relation_id)).to eq([ first.relation_id ])
    expect(first_page).to have_attributes(has_more: true)
    expect(second_page.items.map(&:relation_id)).to eq([ second.relation_id ])
    expect(second_page).to have_attributes(has_more: true)
    expect(second_page.continuation_cursor).to have_attributes(through_observed_sequence: nil)
    expect(later_page.items.map(&:relation_id)).to eq([ third.relation_id ])
    expect(later_page.items.sole.declared.global_position).to be <
      first_page.items.sole.declared.global_position
  end

  it "surfaces a later supersession and replacement from completed relation cursors" do
    parent, = create_observed_artifact(title: "Parent", source_locator: "sup/parent.md")
    original_child, = create_observed_artifact(title: "Original", source_locator: "sup/original.md")
    replacement_child, = create_observed_artifact(
      title: "Replacement",
      source_locator: "sup/replacement.md"
    )
    original = create_relation(parent:, child: original_child, global_position: 100)
    initial = relation_query.call(
      artifact_id: parent.artifact_id,
      direction: "outgoing",
      include_superseded: true,
      limit: 10
    ).value!.data.page
    replacement_id = "018f0f4d-4e45-7abc-8def-000000000192"
    create(
      :coordinator_read_development_artifact_relation_supersession,
      relation: original,
      replacement_relation_id: replacement_id,
      observed_sequence: original.observed_sequence + 1
    )

    updated = relation_query.call(
      artifact_id: parent.artifact_id,
      direction: "outgoing",
      include_superseded: true,
      cursor: initial.continuation_cursor.to_h,
      limit: 10
    ).value!.data.page
    create_relation(
      parent:,
      child: replacement_child,
      relation_id: replacement_id,
      global_position: 200,
      observed_sequence: original.observed_sequence + 2
    )
    converged = relation_query.call(
      artifact_id: parent.artifact_id,
      direction: "outgoing",
      include_superseded: true,
      cursor: updated.continuation_cursor.to_h,
      limit: 10
    ).value!.data.page

    expect(initial).to have_attributes(
      items: [ have_attributes(relation_id: original.relation_id, status: "active") ],
      has_more: false
    )
    expect(updated.items).to contain_exactly(
      have_attributes(
        relation_id: original.relation_id,
        status: "superseded",
        replacement_relation_id: replacement_id
      )
    )
    expect(converged.items).to contain_exactly(
      have_attributes(relation_id: replacement_id, status: "active")
    )
  end

  it "reports absent, unique, and ambiguous exact locator matches without selecting a revision" do
    first, = create_observed_artifact(
      source_locator: "docs/api.md",
      source_revision: "commit-a",
      current_global_position: 100
    )
    second, = create_observed_artifact(
      source_locator: "docs/api.md",
      source_revision: "commit-b",
      current_global_position: 200
    )

    ambiguous = locator_query.call(
      scope: "project:factory",
      source_kind: "local_file",
      locator: "docs/api.md",
      limit: 10
    ).value!
    exact = locator_query.call(
      scope: "project:factory",
      source_kind: "local_file",
      locator: "docs/api.md",
      source_revision: "commit-a",
      limit: 10
    ).value!
    absent = locator_query.call(
      scope: "project:factory",
      source_kind: "local_file",
      locator: "docs/missing.md",
      limit: 10
    ).value!

    expect(ambiguous.data.page).to have_attributes(
      resolution: "ambiguous",
      items: contain_exactly(
        have_attributes(artifact_id: first.artifact_id),
        have_attributes(artifact_id: second.artifact_id)
      )
    )
    expect(ambiguous.next_actions.map(&:tool)).to all(eq("development_artifact_locator_resolve"))
    expect(ambiguous.next_actions.map { _1.arguments.source_revision }).to contain_exactly(
      "commit-a",
      "commit-b"
    )
    expect(exact.data.page).to have_attributes(
      resolution: "unique",
      items: [ have_attributes(artifact_id: first.artifact_id) ]
    )
    expect(exact.next_actions.sole).to have_attributes(
      tool: "development_artifact_content_get",
      arguments: have_attributes(artifact_id: first.artifact_id)
    )
    expect(absent.data.page).to have_attributes(resolution: "absent", items: [])
    expect(absent.warnings.sole).to include("Projection lag")
    expect(absent.next_actions.sole).to have_attributes(tool: "development_artifact_locator_resolve")
  end

  it "returns exact historical observations when unchanged content has multiple captures" do
    artifact = create(
      :coordinator_read_development_artifact,
      source_locator: "docs/unchanged.md",
      content_text: "unchanged\n",
      content_byte_size: 10
    )
    first = create(
      :coordinator_read_development_artifact_observation,
      artifact:,
      source_revision: "commit-a",
      current_global_position: 100
    )
    second = create(
      :coordinator_read_development_artifact_observation,
      artifact:,
      source_revision: "commit-b",
      current_global_position: 200
    )

    history = locator_query.call(
      scope: artifact.scope,
      source_kind: artifact.source_kind,
      locator: artifact.source_locator,
      limit: 10
    ).value!.data.page
    first_exact = Coordinator::Read::Queries::DevelopmentArtifactGet.new.call(
      artifact_id: artifact.artifact_id,
      observation_id: first.observation_id
    ).value!.data.artifact.artifact
    second_exact = Coordinator::Read::Queries::DevelopmentArtifactGet.new.call(
      artifact_id: artifact.artifact_id,
      observation_id: second.observation_id
    ).value!.data.artifact.artifact

    expect(history).to have_attributes(resolution: "ambiguous")
    expect(history.items.map(&:observation_id)).to contain_exactly(
      first.observation_id,
      second.observation_id
    )
    expect(first_exact.source.revision).to eq("commit-a")
    expect(second_exact.source.revision).to eq("commit-b")
  end

  it "builds exact-revision and continuation actions on locator pages" do
    expected = %w[commit-a commit-b commit-c].to_h do |revision|
      artifact, = create_observed_artifact(
        source_locator: "docs/paged.md",
        source_revision: revision,
        current_global_position: 100 + (revision[-1].ord * 10)
      )
      [ revision, artifact.artifact_id ]
    end

    cursor = nil
    observed = {}
    loop do
      input = {
        scope: "project:factory",
        source_kind: "local_file",
        locator: "docs/paged.md",
        limit: 1
      }
      input[:cursor] = cursor if cursor
      result = locator_query.call(input).value!
      exact_action = result.next_actions.find { _1.arguments.to_h.key?(:source_revision) }
      expect(exact_action).to be_a(Coordinator::Read::NextAction)

      exact = locator_query.call(exact_action.arguments.to_h).value!
      revision = exact_action.arguments.source_revision
      expect(exact.data.page).to have_attributes(
        resolution: "unique",
        items: [ have_attributes(artifact_id: expected.fetch(revision)) ]
      )
      observed[revision] = exact.data.page.items.sole.artifact_id

      break unless result.data.page.has_more

      continuation = result.next_actions.find { !_1.arguments.to_h.key?(:source_revision) }
      expect(continuation).to be_a(Coordinator::Read::NextAction)
      cursor = continuation.arguments.cursor.to_h
    end

    expect(observed).to eq(expected)
  end

  it "keeps scopes, explicit null revisions, normalized paths, and URLs caller-owned" do
    unversioned, = create_observed_artifact(
      source_locator: "docs/api.md",
      source_revision: nil
    )
    other_scope, = create_observed_artifact(
      scope: "project:beta",
      source_locator: "docs/api.md",
      source_revision: nil
    )
    url = "https://example.test/reference?page=1"
    web, = create_observed_artifact(
      source_kind: "web_page",
      source_locator: url,
      source_revision: nil
    )

    explicit_nil = locator_query.call(
      scope: "project:factory",
      source_kind: "local_file",
      locator: "docs/api.md",
      source_revision: nil
    ).value!.data.page
    beta = locator_query.call(
      scope: "project:beta",
      source_kind: "local_file",
      locator: "docs/api.md"
    ).value!.data.page
    unresolved_parent_segment = locator_query.call(
      scope: "project:factory",
      source_kind: "local_file",
      locator: "guide/../docs/api.md"
    ).value!.data.page
    exact_url = locator_query.call(
      scope: "project:factory",
      source_kind: "web_page",
      locator: url
    ).value!.data.page

    expect(explicit_nil).to have_attributes(
      resolution: "unique",
      items: [ have_attributes(artifact_id: unversioned.artifact_id) ]
    )
    expect(beta.items.sole).to have_attributes(artifact_id: other_scope.artifact_id)
    expect(unresolved_parent_segment).to have_attributes(resolution: "absent", items: [])
    expect(exact_url.items.sole).to have_attributes(artifact_id: web.artifact_id)
  end

  def create_observed_artifact(current_global_position: nil, **attributes)
    observation_attributes = attributes.slice(
      :scope,
      :title,
      :kind,
      :labels,
      :source_kind,
      :source_locator,
      :source_revision,
      :source_observed_at,
      :source_collector
    )
    artifact = create(:coordinator_read_development_artifact, **attributes)
    observation_attributes[:current_global_position] = current_global_position if current_global_position
    observation = create(
      :coordinator_read_development_artifact_observation,
      artifact:,
      **observation_attributes
    )
    [ artifact, observation ]
  end

  def create_relation(
    parent:,
    child:,
    global_position:,
    relation_id: nil,
    observed_sequence: nil
  )
    attributes = {
      source_artifact: parent,
      target_id: child.artifact_id,
      declared_global_position: global_position
    }
    attributes[:relation_id] = relation_id if relation_id
    attributes[:observed_sequence] = observed_sequence if observed_sequence
    create(:coordinator_read_development_artifact_relation, **attributes)
  end

  def relation_query
    Coordinator::Read::Queries::DevelopmentArtifactRelationList.new
  end

  def locator_query
    Coordinator::Read::Queries::DevelopmentArtifactLocatorResolve.new
  end
end
