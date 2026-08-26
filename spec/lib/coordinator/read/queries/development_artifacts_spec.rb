# frozen_string_literal: true

RSpec.describe "Development Artifact queries", :event_store, :read_model do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:capture) do
    Coordinator::Write::Operations::ExecuteCaptureDevelopmentArtifact.new(event_store:)
  end
  let(:declare_relation) do
    Coordinator::Write::Operations::ExecuteDeclareDevelopmentArtifactRelation.new(event_store:)
  end
  let(:projector) { Coordinator::Read::Projectors::DevelopmentArtifactsV1.new }
  let(:streams) { Coordinator::Write::StreamFactory.new }

  it "serves stale-available metadata separately from focused content" do
    artifact_id = capture_and_project(capture_input)

    get = Coordinator::Read::Queries::DevelopmentArtifactGet.new.call(artifact_id:).value!
    content = Coordinator::Read::Queries::DevelopmentArtifactContentGet.new.call(artifact_id:).value!

    expect(get).to have_attributes(status: "ok", warnings: [])
    expect(get.data.artifact.artifact).to have_attributes(
      artifact_id:,
      content_sha256: a_string_matching(/\Asha256:/)
    )
    expect(get.to_h.to_s).not_to include("first document")
    expect(content).to have_attributes(status: "ok")
    expect(content.data.content).to have_attributes(
      text: "first document\n",
      base64: nil,
      media_type: "text/markdown"
    )
    expect(content.warnings.sole).to include("passive data")
  end

  it "lists in global order with all-label and exact relation-target filters" do
    first = capture_and_project(capture_input)
    second = capture_and_project(
      capture_input(
        command_id: "cmd-query-second",
        locator: "second.md",
        title: "Second",
        labels: %w[docs second-only]
      )
    )
    capture_and_project(
      capture_input(
        command_id: "cmd-query-third",
        locator: "third.log",
        title: "Third",
        kind: "verification_evidence",
        labels: %w[logs]
      )
    )
    relation = declare_relation.call(
      command_id: "cmd-query-relation",
      actor: { kind: "agent", id: "agent-query" },
      source_artifact_id: second,
      relation: "documents",
      target: { kind: "build", id: "build-1" },
      attributes: { path: "notes/second.md" }
    )
    expect(relation).to be_success
    artifact_events(second).last.then { projector.call(_1) }

    labels = Coordinator::Read::Queries::DevelopmentArtifactList.new.call(
      labels: %w[docs second-only],
      limit: 10
    ).value!
    related = Coordinator::Read::Queries::DevelopmentArtifactList.new.call(
      relation_target: { kind: "build", id: "build-1" },
      limit: 10
    ).value!
    page_one = Coordinator::Read::Queries::DevelopmentArtifactList.new.call(limit: 1).value!
    page_two = Coordinator::Read::Queries::DevelopmentArtifactList.new.call(
      after_global_position: page_one.data.page.next_global_position,
      limit: 10
    ).value!

    expect(labels.data.page.items.map(&:artifact_id)).to eq([ second ])
    expect(related.data.page.items.map(&:artifact_id)).to eq([ second ])
    expect(page_one.data.page).to have_attributes(has_more: true)
    expect(page_one.data.page.items.map(&:artifact_id)).to eq([ first ])
    expect(page_two.data.page.items.map(&:artifact_id)).to include(second)
  end

  it "traverses directed mixed relationships with multiple parents and available peer summaries" do
    first_parent = capture_and_project(capture_input(command_id: "cmd-parent-1", locator: "p1.md"))
    second_parent = capture_and_project(capture_input(command_id: "cmd-parent-2", locator: "p2.md"))
    child = capture_and_project(capture_input(command_id: "cmd-child", locator: "child.md"))
    first = declare_and_project(
      command_id: "cmd-edge-1",
      source: first_parent,
      target: child,
      relation: "references",
      attributes: { path: "child.md", normalized_locator: "child.md" }
    )
    second = declare_and_project(
      command_id: "cmd-edge-2",
      source: second_parent,
      target: child,
      relation: "contains"
    )

    incoming = relation_query.call(
      artifact_id: child,
      direction: "incoming",
      limit: 10
    ).value!.data.page
    filtered = relation_query.call(
      artifact_id: child,
      direction: "incoming",
      relation: "references",
      limit: 10
    ).value!.data.page
    outgoing = relation_query.call(
      artifact_id: first_parent,
      direction: "outgoing",
      limit: 10
    ).value!.data.page
    first_page = relation_query.call(
      artifact_id: child,
      direction: "incoming",
      limit: 1
    ).value!.data.page
    second_page = relation_query.call(
      artifact_id: child,
      direction: "incoming",
      cursor: first_page.continuation_cursor.to_h,
      limit: 1
    ).value!.data.page

    expect(incoming.items.map(&:relation_id)).to contain_exactly(first, second)
    expect(incoming.items).to all(have_attributes(direction: "incoming", peer_kind: "artifact"))
    expect(incoming.items.map { _1.peer_artifact.artifact_id }).to contain_exactly(
      first_parent,
      second_parent
    )
    expect(filtered.items.map(&:relation_id)).to eq([ first ])
    expect(first_page).to have_attributes(has_more: true)
    expect(
      first_page.items.map(&:relation_id) + second_page.items.map(&:relation_id)
    ).to eq([ first, second ])
    expect(second_page.continuation_cursor).to have_attributes(
      after_observed_sequence: be_positive,
      through_observed_sequence: nil
    )
    expect(outgoing.items.sole).to have_attributes(
      direction: "outgoing",
      peer_id: child,
      peer_artifact: have_attributes(artifact_id: child),
      relation_attributes: have_attributes(path: "child.md", normalized_locator: "child.md")
    )
  end

  it "continues across projection convergence when an older declaration arrives late" do
    parent = capture_and_project(capture_input(command_id: "cmd-late-parent", locator: "parent.md"))
    child = capture_and_project(capture_input(command_id: "cmd-late-child", locator: "child.md"))
    first_id = declare_relation.call(
      relation_input(command_id: "cmd-late-edge-1", source: parent, target: child)
    ).value!.data.relation_id
    second_id = declare_relation.call(
      relation_input(command_id: "cmd-late-edge-2", source: parent, target: child, relation: "contains")
    ).value!.data.relation_id
    declarations = artifact_events(parent).select do |event|
      event.type == "DevelopmentArtifactRelationDeclared"
    end
    projector.call(declarations.last)

    first_page = relation_query.call(
      artifact_id: parent,
      direction: "outgoing",
      limit: 1
    ).value!.data.page
    expect(first_page.items.map(&:relation_id)).to eq([ second_id ])
    expect(first_page).to have_attributes(has_more: false)

    projector.call(declarations.first)
    converged = relation_query.call(
      artifact_id: parent,
      direction: "outgoing",
      cursor: first_page.continuation_cursor.to_h,
      limit: 1
    ).value!.data.page
    expect(converged.items.map(&:relation_id)).to eq([ first_id ])
    expect(converged.items.sole.declared.global_position).to be < first_page.items.sole.declared.global_position
  end

  it "reports zero, one, or multiple exact locator matches without selecting a revision" do
    first = capture_and_project(
      capture_input(
        command_id: "cmd-locator-v1",
        locator: "docs/api.md",
        revision: "commit-a",
        text: "api v1\n"
      )
    )
    second = capture_and_project(
      capture_input(
        command_id: "cmd-locator-v2",
        locator: "docs/api.md",
        revision: "commit-b",
        text: "api v2\n"
      )
    )

    ambiguous = locator_query.call(
      scope: "project:alpha",
      source_kind: "local_file",
      locator: "docs/api.md",
      limit: 10
    ).value!
    exact = locator_query.call(
      scope: "project:alpha",
      source_kind: "local_file",
      locator: "docs/api.md",
      source_revision: "commit-a",
      limit: 10
    ).value!
    absent = locator_query.call(
      scope: "project:alpha",
      source_kind: "local_file",
      locator: "docs/missing.md",
      limit: 10
    ).value!

    expect(ambiguous.data.page).to have_attributes(
      resolution: "ambiguous",
      items: contain_exactly(
        have_attributes(artifact_id: first),
        have_attributes(artifact_id: second)
      )
    )
    expect(ambiguous.next_actions.map(&:tool)).to all(eq("development_artifact_locator_resolve"))
    expect(ambiguous.next_actions.map { _1.arguments.source_revision }).to contain_exactly(
      "commit-a",
      "commit-b"
    )
    expect(exact.data.page).to have_attributes(
      resolution: "unique",
      items: [ have_attributes(artifact_id: first) ]
    )
    expect(exact.next_actions.sole).to have_attributes(
      tool: "development_artifact_content_get",
      arguments: have_attributes(artifact_id: first)
    )
    expect(absent.data.page).to have_attributes(resolution: "absent", items: [])
    expect(absent.warnings.sole).to include("Projection lag")
    expect(absent.next_actions.sole).to have_attributes(
      tool: "development_artifact_locator_resolve"
    )
  end

  it "keeps scopes, explicit null revisions, normalized paths, and URLs caller-owned" do
    unversioned = capture_and_project(
      capture_input(command_id: "cmd-locator-unversioned", locator: "docs/api.md")
    )
    other_scope = capture_and_project(
      capture_input(
        command_id: "cmd-locator-other-scope",
        locator: "docs/api.md",
        scope: "project:beta"
      )
    )
    url = "https://example.test/reference?page=1"
    web = capture_and_project(
      capture_input(
        command_id: "cmd-locator-web",
        locator: url,
        source_kind: "web_page"
      )
    )

    explicit_nil = locator_query.call(
      scope: "project:alpha",
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
      scope: "project:alpha",
      source_kind: "local_file",
      locator: "guide/../docs/api.md"
    ).value!.data.page
    exact_url = locator_query.call(
      scope: "project:alpha",
      source_kind: "web_page",
      locator: url
    ).value!.data.page

    expect(explicit_nil).to have_attributes(
      resolution: "unique",
      items: [ have_attributes(artifact_id: unversioned) ]
    )
    expect(beta.items.sole).to have_attributes(artifact_id: other_scope)
    expect(unresolved_parent_segment).to have_attributes(resolution: "absent", items: [])
    expect(exact_url.items.sole).to have_attributes(artifact_id: web)
  end

  it "continues locator resolution when an older capture is projected late" do
    older = capture.call(
      capture_input(
        command_id: "cmd-locator-late-older",
        locator: "docs/versioned.md",
        revision: "older",
        text: "older\n"
      )
    ).value!.data.artifact_id
    newer = capture.call(
      capture_input(
        command_id: "cmd-locator-late-newer",
        locator: "docs/versioned.md",
        revision: "newer",
        text: "newer\n"
      )
    ).value!.data.artifact_id
    projector.call(artifact_events(newer).sole)

    first_page = locator_query.call(
      scope: "project:alpha",
      source_kind: "local_file",
      locator: "docs/versioned.md",
      limit: 1
    ).value!.data.page
    expect(first_page).to have_attributes(resolution: "unique", has_more: false)
    expect(first_page.items.sole).to have_attributes(artifact_id: newer)

    projector.call(artifact_events(older).sole)
    converged = locator_query.call(
      scope: "project:alpha",
      source_kind: "local_file",
      locator: "docs/versioned.md",
      cursor: first_page.continuation_cursor.to_h,
      limit: 1
    ).value!.data.page

    expect(converged).to have_attributes(resolution: "ambiguous")
    expect(converged.items.sole).to have_attributes(artifact_id: older)
    expect(converged.items.sole.captured.global_position).to be <
      first_page.items.sole.captured.global_position
  end

  def capture_and_project(input)
    result = capture.call(input)
    expect(result).to be_success
    artifact_id = result.value!.data.artifact_id
    artifact_events(artifact_id).each { projector.call(_1) }
    artifact_id
  end

  def declare_and_project(command_id:, source:, target:, relation:, attributes: {})
    result = declare_relation.call(
      relation_input(command_id:, source:, target:, relation:, attributes:)
    )
    expect(result).to be_success
    event = artifact_events(source).find do |candidate|
      candidate.data.dig("artifact_relation", "relation_id") == result.value!.data.relation_id
    end
    projector.call(event)
    result.value!.data.relation_id
  end

  def relation_input(command_id:, source:, target:, relation: "derived_from", attributes: {})
    {
      command_id:,
      actor: { kind: "agent", id: "agent-query" },
      source_artifact_id: source,
      relation:,
      target: { kind: "artifact", id: target },
      attributes:
    }
  end

  def relation_query
    Coordinator::Read::Queries::DevelopmentArtifactRelationList.new
  end

  def locator_query
    Coordinator::Read::Queries::DevelopmentArtifactLocatorResolve.new
  end

  def capture_input(
    command_id: "cmd-query-first",
    locator: "first.md",
    title: "First",
    kind: "documentation",
    labels: %w[docs review imported],
    scope: "project:alpha",
    source_kind: "local_file",
    revision: nil,
    text: "first document\n"
  )
    {
      command_id:,
      actor: { kind: "agent", id: "agent-query" },
      scope:,
      title:,
      kind:,
      labels:,
      content: {
        encoding: "utf-8",
        media_type: "text/markdown",
        text:
      },
      source: {
        kind: source_kind,
        locator:,
        revision:,
        observed_at: "2026-08-25T16:00:00.000000Z",
        collector: "spec/v1"
      }
    }
  end

  def artifact_events(artifact_id)
    event_store.read(
      streams.development_artifact(artifact_id),
      Coordinator::Write::EventQueries::DEVELOPMENT_ARTIFACT_HISTORY
    )
  end
end
