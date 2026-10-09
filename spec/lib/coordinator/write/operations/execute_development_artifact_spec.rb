# frozen_string_literal: true

RSpec.describe "Development Artifact write operations", :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:capture) { Coordinator::Write::Operations::ExecuteCaptureDevelopmentArtifact.new(event_store:) }
  let(:update) { Coordinator::Write::Operations::ExecuteUpdateDevelopmentArtifact.new(event_store:) }
  let(:classification) do
    Coordinator::Write::Operations::ExecuteCorrectDevelopmentArtifactClassification.new(event_store:)
  end
  let(:declare_relation) do
    Coordinator::Write::Operations::ExecuteDeclareDevelopmentArtifactRelation.new(event_store:)
  end

  it "captures a fresh Artifact and Observation as granular facts with typed metadata" do
    result = capture.call(capture_input)

    expect(result).to be_success
    expect(result.value!.data).to have_attributes(outcome: "captured")
    expect(result.value!.emitted_events.map(&:type)).to eq(
      %w[
        DevelopmentArtifactCreated
        DevelopmentArtifactScopeChanged
        DevelopmentArtifactTitleChanged
        DevelopmentArtifactKindChanged
        DevelopmentArtifactSourceChanged
        DevelopmentArtifactContentChanged
        DevelopmentArtifactLabelAdded
        DevelopmentArtifactLabelAdded
        DevelopmentArtifactObservationRecorded
        DevelopmentArtifactObservationFactLinked
        DevelopmentArtifactObservationFactLinked
        DevelopmentArtifactObservationFactLinked
        DevelopmentArtifactObservationFactLinked
        DevelopmentArtifactObservationFactLinked
        DevelopmentArtifactObservationFactLinked
        DevelopmentArtifactObservationFactLinked
        DevelopmentArtifactObservationFactLinked
      ]
    )

    artifact = result.value!.data
    persisted = artifact_events(artifact.artifact_id)
    expect(persisted.map(&:type)).to eq(
      %w[
        DevelopmentArtifactCreated
        DevelopmentArtifactScopeChanged
        DevelopmentArtifactTitleChanged
        DevelopmentArtifactKindChanged
        DevelopmentArtifactSourceChanged
        DevelopmentArtifactContentChanged
        DevelopmentArtifactLabelAdded
        DevelopmentArtifactLabelAdded
      ]
    )
    expect(persisted.map(&:stream_revision)).to eq((0..7).to_a)
    expect(persisted.map(&:created_at)).to all(be_a(Time))
    expect(persisted.map { _1.data.keys.sort }).to eq([
      [ "artifact_id" ], [ "artifact_id", "scope" ], [ "artifact_id", "title" ],
      [ "artifact_id", "kind" ], [ "artifact_id", "source_kind", "locator", "revision", "observed_at" ],
      [ "artifact_id", "content" ], [ "artifact_id", "label" ], [ "artifact_id", "label" ]
    ].map(&:sort))

    source = persisted.fetch(4)
    expect(source.metadata).to include(
      "collector" => "spec/v1",
      "policy_version" => "development-artifact-repository/v2"
    )
    content = persisted.fetch(5)
    expect(content.data).to eq("artifact_id" => artifact.artifact_id, "content" => "hello\n")
    expect(content.metadata).to include(
      "encoding" => "utf-8",
      "media_type" => "text/markdown",
      "byte_size" => 6,
      "content_sha256" => a_string_matching(/\Asha256:[0-9a-f]{64}\z/)
    )
    expect(content.data).not_to have_key("content_sha256")

    observations = observation_events(artifact.observation_id)
    expect(observations.map(&:type)).to eq(
      [ "DevelopmentArtifactObservationRecorded" ] +
        Array.new(8, "DevelopmentArtifactObservationFactLinked")
    )
    expect(observations.drop(1).map { _1.data.fetch("role") }).to eq(
      %w[created scope title kind source content label label]
    )
    expect(observations.drop(1).map { _1.data.dig("observed_fact", "stream_revision") }).to eq((0..7).to_a)
  end

  it "allocates a new Artifact and Observation identity for every capture" do
    first = capture.call(capture_input(command_id: "cmd-artifact-first"))
    second = capture.call(capture_input(command_id: "cmd-artifact-second"))

    expect([ first, second ]).to all(be_success)
    expect(second.value!.data.artifact_id).not_to eq(first.value!.data.artifact_id)
    expect(second.value!.data.observation_id).not_to eq(first.value!.data.observation_id)
    expect(artifact_events(first.value!.data.artifact_id).length).to eq(8)
    expect(artifact_events(second.value!.data.artifact_id).length).to eq(8)
  end

  it "updates one property with its expected stream revision" do
    captured = capture.call(capture_input).value!.data
    current_revision = artifact_events(captured.artifact_id).last.stream_revision

    result = update.call(
      update_input(
        command_id: "cmd-artifact-title-update",
        artifact_id: captured.artifact_id,
        expected_revision: current_revision,
        changes: { title: "Guide" }
      )
    )

    expect(result).to be_success
    expect(result.value!.data).to have_attributes(
      artifact_id: captured.artifact_id,
      resulting_stream_revision: current_revision + 1,
      changed_properties: [ "title" ],
      outcome: "updated"
    )
    expect(artifact_events(captured.artifact_id).last).to have_attributes(
      type: "DevelopmentArtifactTitleChanged",
      stream_revision: current_revision + 1,
      data: { "artifact_id" => captured.artifact_id, "title" => "Guide" }
    )
  end

  it "updates multiple properties atomically and records each granular fact" do
    captured = capture.call(capture_input).value!.data
    current_revision = artifact_events(captured.artifact_id).last.stream_revision

    result = update.call(
      update_input(
        command_id: "cmd-artifact-multi-update",
        artifact_id: captured.artifact_id,
        expected_revision: current_revision,
        changes: { scope: "project:beta", title: "Guide", labels: %w[docs reviewed] }
      )
    )

    expect(result).to be_success
    expect(result.value!.data.changed_properties).to contain_exactly("scope", "title", "labels")
    new_events = artifact_events(captured.artifact_id).drop(current_revision + 1)
    expect(new_events.map(&:type)).to eq(
      %w[
        DevelopmentArtifactScopeChanged
        DevelopmentArtifactTitleChanged
        DevelopmentArtifactLabelAdded
        DevelopmentArtifactLabelRemoved
      ]
    )
    expect(new_events.map(&:stream_revision)).to eq((current_revision + 1..current_revision + 4).to_a)
  end

  it "returns a no-op without appending facts" do
    captured = capture.call(capture_input).value!.data
    current_revision = artifact_events(captured.artifact_id).last.stream_revision

    result = update.call(
      update_input(
        command_id: "cmd-artifact-no-op",
        artifact_id: captured.artifact_id,
        expected_revision: current_revision,
        changes: { title: "README" }
      )
    )

    expect(result).to be_success
    expect(result.value!.data).to have_attributes(outcome: "existing", resulting_stream_revision: current_revision)
    expect(artifact_events(captured.artifact_id).last.stream_revision).to eq(current_revision)
    expect(result.value!.emitted_events).to be_empty
  end

  it "rejects a stale expected revision without partial writes" do
    captured = capture.call(capture_input).value!.data
    current_revision = artifact_events(captured.artifact_id).last.stream_revision

    result = update.call(
      update_input(
        command_id: "cmd-artifact-stale-update",
        artifact_id: captured.artifact_id,
        expected_revision: current_revision - 1,
        changes: { title: "Stale" }
      )
    )

    expect(result).to be_failure
    expect(result.failure).to have_attributes(
      code: :development_artifact_revision_conflict,
      details: {
        artifact_id: captured.artifact_id,
        expected_revision: current_revision - 1,
        current_revision:
      }
    )
    expect(artifact_events(captured.artifact_id).last.stream_revision).to eq(current_revision)
  end

  it "records a content metadata-only change as a ContentChanged fact" do
    captured = capture.call(capture_input).value!.data
    current_revision = artifact_events(captured.artifact_id).last.stream_revision

    result = update.call(
      update_input(
        command_id: "cmd-artifact-media-type-update",
        artifact_id: captured.artifact_id,
        expected_revision: current_revision,
        changes: {
          content: { encoding: "utf-8", media_type: "text/plain", text: "hello\n" }
        }
      )
    )

    expect(result).to be_success
    event = artifact_events(captured.artifact_id).last
    expect(event).to have_attributes(type: "DevelopmentArtifactContentChanged")
    expect(event.data).to eq("artifact_id" => captured.artifact_id, "content" => "hello\n")
    expect(event.metadata).to include("media_type" => "text/plain", "byte_size" => 6)
  end

  it "corrects classification through property facts, a correction fact, and links" do
    captured = capture.call(capture_input).value!.data

    result = classification.call(
      classification_input(
        command_id: "cmd-artifact-classification",
        observation_id: captured.observation_id,
        expected_revision: 1,
        title: "Guide",
        labels: %w[docs reviewed]
      )
    )

    expect(result).to be_success
    expect(result.value!.data).to have_attributes(
      artifact_id: captured.artifact_id,
      observation_id: captured.observation_id,
      classification_revision: 2,
      title: "Guide",
      kind: "documentation",
      labels: %w[docs reviewed],
      outcome: "corrected"
    )
    expect(result.value!.emitted_events.map(&:type)).to eq(
      %w[
        DevelopmentArtifactTitleChanged
        DevelopmentArtifactLabelAdded
        DevelopmentArtifactLabelRemoved
        DevelopmentArtifactClassificationCorrectionRecorded
        DevelopmentArtifactObservationFactLinked
        DevelopmentArtifactObservationFactLinked
        DevelopmentArtifactObservationFactLinked
      ]
    )

    artifact = artifact_events(captured.artifact_id)
    expect(artifact.last(3).map(&:type)).to eq(
      %w[
        DevelopmentArtifactTitleChanged
        DevelopmentArtifactLabelAdded
        DevelopmentArtifactLabelRemoved
      ]
    )
    correction = observation_events(captured.observation_id).fetch(9)
    expect(correction).to have_attributes(
      type: "DevelopmentArtifactClassificationCorrectionRecorded",
      data: {
        "artifact_id" => captured.artifact_id,
        "observation_id" => captured.observation_id,
        "classification_revision" => 2,
        "reason" => "Improve imported classification"
      }
    )
    expect(correction.metadata).to include(
      "classifier" => "agent-1",
      "policy_version" => "development-artifact-repository/v2"
    )
    links = observation_events(captured.observation_id).last(3)
    expect(links.map { _1.data.dig("observed_fact", "event_id") }).to eq(artifact.last(3).map(&:id))
    expect(links.map { _1.data.fetch("role") }).to eq(%w[title label label])
  end

  it "returns a classification no-op and rejects a stale classification revision" do
    captured = capture.call(capture_input).value!.data
    unchanged = classification.call(
      classification_input(
        command_id: "cmd-artifact-classification-no-op",
        observation_id: captured.observation_id,
        expected_revision: 1,
        title: "README",
        labels: %w[docs imported]
      )
    )

    expect(unchanged).to be_success
    expect(unchanged.value!.data.outcome).to eq("existing")
    expect(unchanged.value!.emitted_events).to be_empty

    corrected = classification.call(
      classification_input(
        command_id: "cmd-artifact-classification-correct",
        observation_id: captured.observation_id,
        expected_revision: 1,
        title: "Guide",
        labels: %w[docs reviewed]
      )
    )
    expect(corrected).to be_success

    stale = classification.call(
      classification_input(
        command_id: "cmd-artifact-classification-stale",
        observation_id: captured.observation_id,
        expected_revision: 1,
        title: "Another guide",
        labels: %w[docs reviewed]
      )
    )
    expect(stale).to be_failure
    expect(stale.failure).to have_attributes(
      code: :development_artifact_classification_revision_conflict,
      details: {
        observation_id: captured.observation_id,
        expected_revision: 1,
        current_revision: 2
      }
    )
  end

  it "declares and idempotently replays relations on independent relation streams" do
    source = capture.call(capture_input(command_id: "cmd-relation-source")).value!.data
    target = capture.call(capture_input(command_id: "cmd-relation-target", locator: "docs/target.md")).value!.data
    input = relation_input(
      command_id: "cmd-relation-declare",
      source: source.artifact_id,
      target: target.artifact_id,
      attributes: { path: "docs/target.md" }
    )

    first = declare_relation.call(input)
    replay = declare_relation.call(input.merge(command_id: "cmd-relation-replay"))

    expect(first).to be_success
    expect(first.value!.data).to have_attributes(outcome: "declared", relation: "references")
    relation_id = first.value!.data.relation_id
    expect(relation_events(relation_id).map(&:type)).to eq([ "DevelopmentArtifactRelationDeclared" ])
    declaration = relation_events(relation_id).sole
    expect(declaration.data).to include(
      "relation_id" => relation_id,
      "source_artifact_id" => source.artifact_id,
      "relation" => "references",
      "target_kind" => "artifact",
      "target_id" => target.artifact_id,
      "path" => "docs/target.md"
    )
    expect(artifact_events(source.artifact_id).map(&:type)).not_to include("DevelopmentArtifactRelationDeclared")

    expect(replay).to be_success
    expect(replay.value!.data).to have_attributes(relation_id:, outcome: "existing")
    expect(replay.value!.emitted_events).to be_empty
    expect(relation_events(relation_id).length).to eq(1)
  end

  it "supersedes a relation by appending to old and replacement relation streams" do
    source = capture.call(capture_input(command_id: "cmd-supersession-source")).value!.data
    first_target = capture.call(capture_input(command_id: "cmd-supersession-first", locator: "docs/first.md")).value!.data
    second_target = capture.call(capture_input(command_id: "cmd-supersession-second", locator: "docs/second.md")).value!.data
    old = declare_relation.call(
      relation_input(
        command_id: "cmd-relation-old",
        source: source.artifact_id,
        target: first_target.artifact_id,
        attributes: { path: "docs/first.md" }
      )
    ).value!.data

    replacement = declare_relation.call(
      relation_input(
        command_id: "cmd-relation-replacement",
        source: source.artifact_id,
        target: second_target.artifact_id,
        attributes: { path: "docs/second.md" },
        supersedes: { relation_id: old.relation_id, reason: "Target was replaced" }
      )
    )

    expect(replacement).to be_success
    new_relation_id = replacement.value!.data.relation_id
    expect(relation_events(new_relation_id).map(&:type)).to eq([ "DevelopmentArtifactRelationDeclared" ])
    expect(relation_events(old.relation_id).map(&:type)).to eq(
      [ "DevelopmentArtifactRelationDeclared", "DevelopmentArtifactRelationSuperseded" ]
    )
    supersession = relation_events(old.relation_id).last
    expect(supersession.data).to eq(
      "relation_id" => old.relation_id,
      "source_artifact_id" => source.artifact_id,
      "replacement_relation_id" => new_relation_id,
      "reason" => "Target was replaced"
    )
    expect(replacement.value!.emitted_events.map(&:type)).to eq(
      [ "DevelopmentArtifactRelationDeclared", "DevelopmentArtifactRelationSuperseded" ]
    )
  end

  def capture_input(
    command_id: "cmd-artifact-capture",
    locator: "docs/readme.md",
    revision: "abc123",
    observed_at: "2026-09-03T12:00:00.000000Z",
    text: "hello\n",
    **overrides
  )
    {
      command_id:,
      actor: { kind: "agent", id: "agent-1" },
      scope: "project:alpha",
      title: "README",
      kind: "documentation",
      labels: %w[docs imported],
      content: { encoding: "utf-8", media_type: "text/markdown", text: },
      source: {
        kind: "local_file", locator:, revision:, observed_at:, collector: "spec/v1"
      }
    }.merge(overrides)
  end

  def update_input(command_id:, artifact_id:, expected_revision:, changes:)
    {
      command_id:,
      actor: { kind: "agent", id: "agent-1" },
      artifact_id:,
      expected_revision:,
      changes:
    }
  end

  def classification_input(command_id:, observation_id:, expected_revision:, title:, labels:)
    {
      command_id:,
      actor: { kind: "agent", id: "agent-1" },
      observation_id:,
      expected_revision:,
      title:,
      kind: "documentation",
      labels:,
      reason: "Improve imported classification"
    }
  end

  def relation_input(command_id:, source:, target:, attributes:, supersedes: nil)
    input = {
      command_id:,
      actor: { kind: "agent", id: "agent-1" },
      source_artifact_id: source,
      relation: "references",
      target: { kind: "artifact", id: target },
      attributes:
    }
    input[:supersedes] = supersedes if supersedes
    input
  end

  def artifact_events(artifact_id)
    event_store.read(
      streams.development_artifact(artifact_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[
          DevelopmentArtifactCreated DevelopmentArtifactScopeChanged DevelopmentArtifactTitleChanged
          DevelopmentArtifactKindChanged DevelopmentArtifactLabelAdded DevelopmentArtifactLabelRemoved
          DevelopmentArtifactSourceChanged DevelopmentArtifactContentChanged
          DevelopmentArtifactRelationDeclared DevelopmentArtifactRelationSuperseded
        ],
        maximum_count: Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_HISTORY_MAXIMUM_COUNT,
        direction: :asc
      )
    )
  end

  def observation_events(observation_id)
    event_store.read(
      streams.development_artifact_observation(observation_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[
          DevelopmentArtifactObservationRecorded DevelopmentArtifactObservationFactLinked
          DevelopmentArtifactClassificationCorrectionRecorded

        ],
        maximum_count: 128,
        direction: :asc
      )
    )
  end

  def relation_events(relation_id)
    event_store.read(
      streams.development_artifact_relation(relation_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[DevelopmentArtifactRelationDeclared DevelopmentArtifactRelationSuperseded],
        maximum_count: 2,
        direction: :asc
      )
    )
  end
end
