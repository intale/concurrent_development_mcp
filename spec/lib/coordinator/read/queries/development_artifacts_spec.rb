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

  def capture_and_project(input)
    result = capture.call(input)
    expect(result).to be_success
    artifact_id = result.value!.data.artifact_id
    artifact_events(artifact_id).each { projector.call(_1) }
    artifact_id
  end

  def capture_input(
    command_id: "cmd-query-first",
    locator: "first.md",
    title: "First",
    kind: "documentation",
    labels: %w[docs review imported]
  )
    {
      command_id:,
      actor: { kind: "agent", id: "agent-query" },
      scope: "project:alpha",
      title:,
      kind:,
      labels:,
      content: {
        encoding: "utf-8",
        media_type: "text/markdown",
        text: "first document\n"
      },
      source: {
        kind: "local_file",
        locator:,
        revision: nil,
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
