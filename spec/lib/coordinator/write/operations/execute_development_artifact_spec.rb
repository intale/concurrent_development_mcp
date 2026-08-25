# frozen_string_literal: true

RSpec.describe "Development Artifact write operations", :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:capture) do
    Coordinator::Write::Operations::ExecuteCaptureDevelopmentArtifact.new(event_store:)
  end
  let(:declare_relation) do
    Coordinator::Write::Operations::ExecuteDeclareDevelopmentArtifactRelation.new(event_store:)
  end
  let(:streams) { Coordinator::Write::StreamFactory.new }

  it "captures canonical bytes atomically with its command and replays exact Artifact identity" do
    first = capture.call(capture_input)
    replay = capture.call(capture_input(command_id: "cmd-artifact-replay"))

    expect(first).to be_success
    expect(first.value!.data).to have_attributes(
      outcome: "captured",
      byte_size: 6,
      content_sha256: a_string_matching(/\Asha256:[0-9a-f]{64}\z/)
    )
    expect(replay).to be_success
    expect(replay.value!.data).to have_attributes(
      artifact_id: first.value!.data.artifact_id,
      outcome: "existing"
    )
    expect(replay.value!.emitted_events).to be_empty
    expect(artifact_events(first.value!.data.artifact_id).map(&:type)).to eq(
      [ "DevelopmentArtifactCaptured" ]
    )
    expect(command_events("cmd-artifact-replay").map(&:type)).to eq([ "CommandCompleted" ])
  end

  it "assigns changed source bytes a different Artifact identity" do
    first = capture.call(capture_input)
    changed = capture.call(capture_input(command_id: "cmd-artifact-changed", text: "second"))

    expect([ first, changed ]).to all(be_success)
    expect(changed.value!.data.artifact_id).not_to eq(first.value!.data.artifact_id)
  end

  it "rejects different immutable fields that collide on the derived Artifact identity" do
    first = capture.call(capture_input)
    conflicting = capture.call(capture_input(command_id: "cmd-artifact-conflict", title: "Other title"))

    expect(first).to be_success
    expect(conflicting).to be_failure
    expect(conflicting.failure.code).to eq(:development_artifact_identity_conflict)
    expect(command_events("cmd-artifact-conflict")).to be_empty
  end

  it "declares an exact relation once and requires both Artifact endpoints" do
    source = capture.call(capture_input).value!.data.artifact_id
    target = capture.call(
      capture_input(command_id: "cmd-artifact-target", locator: "docs/other.md", text: "other")
    ).value!.data.artifact_id
    first = declare_relation.call(relation_input(source:, target:))
    replay = declare_relation.call(
      relation_input(command_id: "cmd-relation-replay", source:, target:)
    )
    missing = declare_relation.call(
      relation_input(
        command_id: "cmd-relation-missing",
        source:,
        target: "artifact:v1:#{'f' * 64}"
      )
    )

    expect(first).to be_success
    expect(first.value!.data.outcome).to eq("declared")
    expect(replay).to be_success
    expect(replay.value!.data).to have_attributes(
      relation_id: first.value!.data.relation_id,
      outcome: "existing"
    )
    expect(replay.value!.emitted_events).to be_empty
    expect(missing.failure.code).to eq(:development_artifact_target_not_found)
    expect(artifact_events(source).map(&:type)).to eq(
      [ "DevelopmentArtifactCaptured", "DevelopmentArtifactRelationDeclared" ]
    )
  end

  def capture_input(command_id: "cmd-artifact-capture", locator: "docs/readme.md", text: "hello\n", **overrides)
    {
      command_id:,
      actor: { kind: "agent", id: "agent-1" },
      scope: "project:alpha",
      title: "README",
      kind: "documentation",
      labels: %w[docs imported],
      content: {
        encoding: "utf-8",
        media_type: "text/markdown",
        text:
      },
      source: {
        kind: "local_file",
        locator:,
        revision: "abc123",
        observed_at: "2026-08-25T16:00:00.000000Z",
        collector: "spec/v1"
      }
    }.merge(overrides)
  end

  def relation_input(command_id: "cmd-relation", source:, target:)
    {
      command_id:,
      actor: { kind: "agent", id: "agent-1" },
      source_artifact_id: source,
      relation: "derived_from",
      target: { kind: "artifact", id: target },
      attributes: {}
    }
  end

  def artifact_events(artifact_id)
    event_store.read(
      streams.development_artifact(artifact_id),
      Coordinator::Write::EventQueries::DEVELOPMENT_ARTIFACT_HISTORY
    )
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_COMPLETION)
  end
end
