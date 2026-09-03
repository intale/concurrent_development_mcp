# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::DevelopmentArtifacts::Update do
  let(:artifact_id) { SecureRandom.uuid_v7 }
  let(:state) do
    content_event = Coordinator::Write::Events::DevelopmentArtifactContentChangedV1.new(
      artifact_id:, content: "before"
    )
    source_event = Coordinator::Write::Events::DevelopmentArtifactSourceChangedV1.new(
      artifact_id:, source_kind: "local_file", locator: "README.md", revision: nil,
      observed_at: "2026-09-03T12:00:00.000000Z"
    )
    Coordinator::Write::Domain::DevelopmentArtifacts::State.reduce(
      [
        Coordinator::Write::Events::DevelopmentArtifactCreatedV1.new(artifact_id:),
        Coordinator::Write::Events::DevelopmentArtifactScopeChangedV1.new(artifact_id:, scope: "project:one"),
        Coordinator::Write::Events::DevelopmentArtifactTitleChangedV1.new(artifact_id:, title: "Original"),
        Coordinator::Write::Events::DevelopmentArtifactKindChangedV1.new(artifact_id:, kind: "documentation"),
        Coordinator::Write::Events::DevelopmentArtifactLabelAddedV1.new(artifact_id:, label: "old"),
        content_event, source_event
      ],
      metadata_by_event: {
        content_event.object_id => {
          "encoding" => "utf-8", "media_type" => "text/markdown", "byte_size" => 6,
          "content_sha256" => "sha256:6db7d803e74f1ffa7d8f5adc0bf95b3e15bf4c8373fffadf546227cc6c6742cb"
        },
        source_event.object_id => { "collector" => "agent" }
      }
    )
  end
  let(:content) do
    Coordinator::Write::DevelopmentArtifacts::ContentBuilder.new.call(
      encoding: "utf-8", media_type: "text/markdown", text: "after"
    ).value!
  end
  let(:source) do
    Coordinator::Write::DevelopmentArtifacts::SourceV1.new(
      kind: "local_file", locator: "README.md", revision: "new", observed_at: "2026-09-03T12:00:00.000000Z",
      collector: "agent"
    )
  end

  it "emits only changed granular property facts" do
    changes = Coordinator::Write::DevelopmentArtifacts::UpdateChangesV1.new(
      title: "Updated", labels: [ "new" ], content:, source:
    )

    result = described_class.new.call(artifact_id:, changes:, state:).value!

    expect(result.outcome).to eq("updated")
    expect(result.changed_properties).to eq(%w[title labels content source])
    expect(result.event_plan.events.map(&:class)).to eq(
      [
        Coordinator::Write::Events::DevelopmentArtifactTitleChangedV1,
        Coordinator::Write::Events::DevelopmentArtifactLabelAddedV1,
        Coordinator::Write::Events::DevelopmentArtifactLabelRemovedV1,
        Coordinator::Write::Events::DevelopmentArtifactContentChangedV1,
        Coordinator::Write::Events::DevelopmentArtifactSourceChangedV1
      ]
    )
    expect(result.event_plan.events.map(&:to_h).join).not_to include("byte_size", "content_sha256", "collector")
  end

  it "returns an existing outcome when every requested property already matches" do
    changes = Coordinator::Write::DevelopmentArtifacts::UpdateChangesV1.new(
      title: "Original", labels: [ "old" ], content: Coordinator::Write::DevelopmentArtifacts::ContentBuilder.new.call(
        encoding: "utf-8", media_type: "text/markdown", text: "before"
      ).value!
    )

    result = described_class.new.call(artifact_id:, changes:, state:).value!

    expect(result).to have_attributes(outcome: "existing", changed_properties: [], event_plan: nil)
  end

  it "treats changed content descriptors as a content change" do
    same_text = Coordinator::Write::DevelopmentArtifacts::ContentBuilder.new.call(
      encoding: "utf-8", media_type: "text/plain", text: "before"
    ).value!
    changes = Coordinator::Write::DevelopmentArtifacts::UpdateChangesV1.new(content: same_text)

    result = described_class.new.call(
      artifact_id:, changes:, state:
    ).value!

    expect(result.changed_properties).to eq([ "content" ])
  end

  it "treats changed source collector metadata as a source change" do
    source_event = state.source
    state_with_collector = Coordinator::Write::Domain::DevelopmentArtifacts::State.reduce(
      [
        state.created,
        state.scope,
        state.title,
        state.kind,
        Coordinator::Write::Events::DevelopmentArtifactLabelAddedV1.new(artifact_id:, label: "old"),
        Coordinator::Write::Events::DevelopmentArtifactContentChangedV1.new(artifact_id:, content: "before"),
        source_event
      ],
      metadata_by_event: { source_event.object_id => { "collector" => "old-agent" } }
    )
    incoming = source.class.new(source.to_h.merge(revision: nil))
    result = described_class.new.call(
      artifact_id:,
      changes: Coordinator::Write::DevelopmentArtifacts::UpdateChangesV1.new(source: incoming),
      state: state_with_collector
    ).value!

    expect(result.changed_properties).to eq([ "source" ])
  end
end
