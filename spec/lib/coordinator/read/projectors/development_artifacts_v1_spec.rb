# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::DevelopmentArtifactsV1, :event_store, :read_model do
  subject(:projector) { described_class.new }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:capture) do
    Coordinator::Write::Operations::ExecuteCaptureDevelopmentArtifact.new(event_store:)
  end
  let(:declare_relation) do
    Coordinator::Write::Operations::ExecuteDeclareDevelopmentArtifactRelation.new(event_store:)
  end
  let(:repository) { Coordinator::Read::Repositories::DevelopmentArtifacts.new }
  let(:streams) { Coordinator::Write::StreamFactory.new }

  it "projects capture and delayed relation delivery idempotently with exact source evidence" do
    source = capture.call(capture_input).value!.data.artifact_id
    target = capture.call(
      capture_input(command_id: "cmd-project-target", locator: "target.bin", binary: true)
    ).value!.data.artifact_id
    declare_relation.call(relation_input(source:, target:))
    source_capture, relation = artifact_events(source)

    projector.call(relation)
    projector.call(relation)
    expect(repository.fetch(source)).to be_nil
    expect(Coordinator::Read::DevelopmentArtifactRelation.count).to eq(1)
    lagging = relation_query.call(
      artifact_id: source,
      direction: "outgoing",
      limit: 10
    ).value!
    expect(lagging.data.page).to have_attributes(artifact: nil)
    expect(lagging.data.page.items.sole).to have_attributes(peer_artifact: nil)
    expect(lagging.warnings.sole).to include("not yet observed")

    projector.call(source_capture)
    projector.call(source_capture)
    view = repository.fetch(source)
    expect(view.artifact).to have_attributes(
      artifact_id: source,
      title: "Captured evidence",
      relationship_count: 1,
      captured: have_attributes(
        event: have_attributes(event_id: source_capture.id, stream_revision: 0),
        global_position: source_capture.global_position,
        causation_id: source_capture.causation_id,
        correlation_id: source_capture.correlation_id
      )
    )
    expect(view.relationships.sole).to have_attributes(
      relation_id: relation.data.fetch("artifact_relation").fetch("relation_id"),
      target: have_attributes(kind: "artifact", id: target),
      peer_artifact: nil
    )
    expect(processed_events.count).to eq(2)
    expect(view.to_h.keys & %i[fresh pending projection_status]).to be_empty
  end

  it "round-trips UTF-8 and binary content without embedding bytes in metadata" do
    text_id = capture.call(capture_input).value!.data.artifact_id
    binary_id = capture.call(
      capture_input(command_id: "cmd-project-binary", locator: "profile.bin", binary: true)
    ).value!.data.artifact_id
    [ text_id, binary_id ].each do |artifact_id|
      artifact_events(artifact_id).each { |event| projector.call(event) }
    end

    text = repository.fetch_content(text_id)
    binary = repository.fetch_content(binary_id)
    expect(text).to have_attributes(text: "evidence\n", base64: nil, encoding: "utf-8")
    expect(binary).to have_attributes(
      text: nil,
      base64: [ "\x00\xFF".b ].pack("m0"),
      encoding: "binary"
    )
    expect(repository.fetch(text_id).to_h.to_s).not_to include("evidence\\n")
  end

  it "projects an out-of-order supersession without hiding its immutable declaration history" do
    source = capture.call(capture_input).value!.data.artifact_id
    old_target = capture.call(
      capture_input(command_id: "cmd-project-old", locator: "old.md")
    ).value!.data.artifact_id
    new_target = capture.call(
      capture_input(command_id: "cmd-project-new", locator: "new.md")
    ).value!.data.artifact_id
    old = declare_relation.call(relation_input(source:, target: old_target)).value!.data
    declare_relation.call(
      relation_input(
        command_id: "cmd-project-correct",
        source:,
        target: new_target,
        supersedes: { relation_id: old.relation_id, reason: "wrong target" }
      )
    )
    events = artifact_events(source)
    declarations = events.select { _1.type == "DevelopmentArtifactRelationDeclared" }
    supersession = events.find { _1.type == "DevelopmentArtifactRelationSuperseded" }

    projector.call(supersession)
    projector.call(supersession)
    expect(Coordinator::Read::DevelopmentArtifactRelationSupersession.count).to eq(1)
    declarations.reverse_each { projector.call(_1) }
    projector.call(events.first)

    page = relation_query.call(
      artifact_id: source,
      direction: "outgoing",
      include_superseded: true,
      limit: 10
    ).value!.data.page
    expect(page.items.map(&:status)).to contain_exactly("active", "superseded")
    superseded = page.items.find { _1.status == "superseded" }
    expect(superseded).to have_attributes(
      relation_id: old.relation_id,
      replacement_relation_id: a_string_matching(/\Aartifact-relation:v1:/),
      supersession_reason: "wrong target",
      superseded: have_attributes(event: have_attributes(type: "DevelopmentArtifactRelationSuperseded"))
    )
    active = relation_query.call(
      artifact_id: source,
      direction: "outgoing",
      limit: 10
    ).value!.data.page
    expect(active.items.map(&:status)).to eq([ "active" ])
  end

  def capture_input(command_id: "cmd-project-source", locator: "evidence.md", binary: false)
    content =
      if binary
        {
          encoding: "binary",
          media_type: "application/octet-stream",
          base64: [ "\x00\xFF".b ].pack("m0")
        }
      else
        { encoding: "utf-8", media_type: "text/markdown", text: "evidence\n" }
      end
    {
      command_id:,
      actor: { kind: "agent", id: "agent-projector" },
      scope: "project:alpha",
      title: "Captured evidence",
      kind: binary ? "performance_profile" : "documentation",
      labels: binary ? %w[binary profile] : %w[docs evidence],
      content:,
      source: {
        kind: "local_file",
        locator:,
        revision: nil,
        observed_at: "2026-08-25T16:00:00.000000Z",
        collector: "spec/v1"
      }
    }
  end

  def relation_input(source:, target:, command_id: "cmd-project-relation", supersedes: nil)
    input = {
      command_id:,
      actor: { kind: "agent", id: "agent-projector" },
      source_artifact_id: source,
      relation: "derived_from",
      target: { kind: "artifact", id: target },
      attributes: {}
    }
    input[:supersedes] = supersedes if supersedes
    input
  end

  def artifact_events(artifact_id)
    event_store.read(
      streams.development_artifact(artifact_id),
      Coordinator::Write::EventQueries::DEVELOPMENT_ARTIFACT_HISTORY
    )
  end

  def processed_events
    Coordinator::Read::ProcessedProjectionEvent.where(
      projection_name: "development-artifacts",
      projection_version: 2
    )
  end

  def relation_query
    Coordinator::Read::Queries::DevelopmentArtifactRelationList.new
  end
end
