# frozen_string_literal: true

RSpec.describe "Development Artifact write operations", :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:capture) do
    Coordinator::Write::Operations::ExecuteCaptureDevelopmentArtifact.new(event_store:)
  end
  let(:correct_classification) do
    Coordinator::Write::Operations::ExecuteCorrectDevelopmentArtifactClassification.new(event_store:)
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
    persisted = artifact_events(first.value!.data.artifact_id).sole
    expect(persisted.type).to eq("DevelopmentArtifactCaptured")
    expect(persisted.metadata.fetch("schema_version")).to eq(2)
    persisted_content = persisted.data.dig("artifact", "content")
    expect(persisted_content).to include("encoding" => "utf-8", "text" => "hello\n")
    expect(persisted_content).not_to have_key("base64")
    expect(command_events("cmd-artifact-replay").map(&:type)).to eq([ "CommandCompleted" ])
  end

  it "assigns changed source bytes a different Artifact identity" do
    first = capture.call(capture_input)
    changed = capture.call(capture_input(command_id: "cmd-artifact-changed", text: "second"))

    expect([ first, changed ]).to all(be_success)
    expect(changed.value!.data.artifact_id).not_to eq(first.value!.data.artifact_id)
  end

  it "corrects observation classification without changing content identity or provenance" do
    first = capture.call(capture_input)
    capture_with_changed_classification = capture.call(
      capture_input(command_id: "cmd-artifact-reclassify", title: "Other title")
    )
    correction = correct_classification.call(
      classification_input(observation_id: first.value!.data.observation_id)
    )
    existing = correct_classification.call(
      classification_input(
        command_id: "cmd-classification-existing",
        observation_id: first.value!.data.observation_id,
        expected_revision: 2
      )
    )
    stale = correct_classification.call(
      classification_input(
        command_id: "cmd-classification-stale",
        observation_id: first.value!.data.observation_id,
        title: "Stale correction"
      )
    )

    expect(first).to be_success
    expect(capture_with_changed_classification).to be_failure
    expect(capture_with_changed_classification.failure.code).to eq(
      :development_artifact_classification_correction_required
    )
    expect(correction).to be_success
    expect(correction.value!.data).to have_attributes(
      artifact_id: first.value!.data.artifact_id,
      observation_id: first.value!.data.observation_id,
      classification_revision: 2,
      title: "Other title",
      outcome: "corrected"
    )
    expect(correction.value!.emitted_events.map(&:type)).to eq(
      [ "DevelopmentArtifactClassificationCorrected" ]
    )
    expect(existing).to be_success
    expect(existing.value!.data.outcome).to eq("existing")
    expect(existing.value!.emitted_events).to be_empty
    expect(stale.failure.code).to eq(:development_artifact_classification_revision_conflict)
    expect(command_events("cmd-artifact-reclassify")).to be_empty
    expect(command_events("cmd-classification-stale")).to be_empty
    expect(observation_events(first.value!.data.observation_id).map(&:type)).to eq(
      %w[DevelopmentArtifactObserved DevelopmentArtifactClassificationCorrected]
    )
  end

  it "records distinct observations for unchanged bytes at two revisions of one locator" do
    first = capture.call(capture_input)
    second = capture.call(
      capture_input(
        command_id: "cmd-artifact-second-observation",
        revision: "def456",
        observed_at: "2026-08-25T16:01:00.000000Z"
      )
    )

    expect([ first, second ]).to all(be_success)
    expect(second.value!.data).to have_attributes(
      artifact_id: first.value!.data.artifact_id,
      outcome: "observed"
    )
    expect(second.value!.data.observation_id).not_to eq(first.value!.data.observation_id)
    expect(artifact_events(first.value!.data.artifact_id).map(&:type)).to eq(
      [ "DevelopmentArtifactCaptured" ]
    )
    expect(observation_events(first.value!.data.observation_id).map(&:type)).to eq(
      [ "DevelopmentArtifactObserved" ]
    )
    expect(observation_events(second.value!.data.observation_id).map(&:type)).to eq(
      [ "DevelopmentArtifactObserved" ]
    )
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
    expect(first.value!.data.target.status).to eq("verified")
    expect(replay).to be_success
    expect(replay.value!.data).to have_attributes(
      relation_id: first.value!.data.relation_id,
      outcome: "existing"
    )
    expect(replay.value!.emitted_events).to be_empty
    expect(missing.failure.code).to eq(:development_artifact_target_not_found)
    expect(missing.failure.details).to include(
      target_kind: "artifact",
      target_id: "artifact:v1:#{'f' * 64}"
    )
    expect(artifact_events(source).map(&:type)).to eq(
      [ "DevelopmentArtifactCaptured", "DevelopmentArtifactRelationDeclared" ]
    )
  end

  it "atomically supersedes an incorrect relation while preserving immutable history" do
    source = capture.call(capture_input).value!.data.artifact_id
    old_target = capture.call(
      capture_input(command_id: "cmd-artifact-old", locator: "docs/old.md", text: "old")
    ).value!.data.artifact_id
    replacement_target = capture.call(
      capture_input(command_id: "cmd-artifact-new", locator: "docs/new.md", text: "new")
    ).value!.data.artifact_id
    old = declare_relation.call(relation_input(source:, target: old_target)).value!.data

    correction_input = relation_input(
      command_id: "cmd-relation-correct",
      source:,
      target: replacement_target,
      supersedes: { relation_id: old.relation_id, reason: "wrong target" }
    )
    correction = declare_relation.call(correction_input)
    replay = declare_relation.call(correction_input)
    semantic_retry = declare_relation.call(
      correction_input.merge(command_id: "cmd-relation-correct-retry")
    )

    expect(correction).to be_success
    expect(correction.value!.data).to have_attributes(
      outcome: "superseded",
      superseded_relation_id: old.relation_id,
      superseded_at: a_string_matching(/Z\z/)
    )
    expect(correction.value!.emitted_events.map(&:type)).to eq(
      %w[DevelopmentArtifactRelationDeclared DevelopmentArtifactRelationSuperseded]
    )
    expect(replay.value!.data).to eq(correction.value!.data)
    expect(semantic_retry.value!.data.outcome).to eq("existing")
    expect(semantic_retry.value!.emitted_events).to be_empty
    expect(artifact_events(source).map(&:type)).to eq(
      %w[
        DevelopmentArtifactCaptured
        DevelopmentArtifactRelationDeclared
        DevelopmentArtifactRelationDeclared
        DevelopmentArtifactRelationSuperseded
      ]
    )

    dead_replacement = declare_relation.call(
      relation_input(command_id: "cmd-relation-dead", source:, target: old_target)
    )
    expect(dead_replacement.failure.code).to eq(:development_artifact_relation_superseded)
  end

  it "denies unknown or redirected supersessions without partial writes" do
    source = capture.call(capture_input).value!.data.artifact_id
    first_target = capture.call(
      capture_input(command_id: "cmd-artifact-first", locator: "docs/first.md", text: "first")
    ).value!.data.artifact_id
    second_target = capture.call(
      capture_input(command_id: "cmd-artifact-second", locator: "docs/second.md", text: "second")
    ).value!.data.artifact_id
    third_target = capture.call(
      capture_input(command_id: "cmd-artifact-third", locator: "docs/third.md", text: "third")
    ).value!.data.artifact_id
    old = declare_relation.call(relation_input(source:, target: first_target)).value!.data
    declare_relation.call(
      relation_input(
        command_id: "cmd-relation-first-correction",
        source:,
        target: second_target,
        supersedes: { relation_id: old.relation_id, reason: "first correction" }
      )
    )

    redirected = declare_relation.call(
      relation_input(
        command_id: "cmd-relation-redirect",
        source:,
        target: third_target,
        supersedes: { relation_id: old.relation_id, reason: "redirect" }
      )
    )
    unknown = declare_relation.call(
      relation_input(
        command_id: "cmd-relation-unknown",
        source:,
        target: third_target,
        supersedes: {
          relation_id: "artifact-relation:v1:#{'f' * 64}",
          reason: "unknown"
        }
      )
    )

    expect(redirected.failure.code).to eq(:development_artifact_relation_already_superseded)
    expect(unknown.failure.code).to eq(:development_artifact_relation_not_found)
    expect(command_events("cmd-relation-redirect")).to be_empty
    expect(command_events("cmd-relation-unknown")).to be_empty
    expect(artifact_events(source).map(&:type).count("DevelopmentArtifactRelationDeclared")).to eq(2)
  end

  it "permits bounded cycles and converges concurrent duplicate declarations" do
    first = capture.call(capture_input).value!.data.artifact_id
    second = capture.call(
      capture_input(command_id: "cmd-cycle-second", locator: "docs/second.md", text: "second")
    ).value!.data.artifact_id

    forward = declare_relation.call(
      relation_input(command_id: "cmd-cycle-forward", source: first, target: second, relation: "contains")
    )
    reverse = declare_relation.call(
      relation_input(command_id: "cmd-cycle-reverse", source: second, target: first, relation: "contains")
    )
    concurrent = 2.times.map do |index|
      Thread.new do
        declare_relation.call(
          relation_input(command_id: "cmd-race-#{index}", source: first, target: second)
        )
      end
    end.map(&:value)

    expect([ forward, reverse ]).to all(be_success)
    expect(concurrent).to all(be_success)
    expect(concurrent.map { _1.value!.data.outcome }).to contain_exactly("declared", "existing")
    relation_ids = artifact_events(first).filter_map do |event|
      event.data.dig("artifact_relation", "relation_id") if event.type == "DevelopmentArtifactRelationDeclared"
    end
    expect(relation_ids.uniq).to eq(relation_ids)
  end

  it "separates active capacity from bounded lifetime history and lets supersession replace an active edge" do
    source = capture.call(capture_input).value!.data.artifact_id
    active = Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_ACTIVE_RELATION_MAXIMUM_COUNT.times.map do |index|
      result = declare_relation.call(
        relation_input(
          command_id: "cmd-limit-#{index}",
          source:,
          target: "https://example.test/#{index}",
          relation: "references",
          target_kind: "external"
        )
      )
      expect(result).to be_success
      result.value!.data
    end

    active_overflow = declare_relation.call(
      relation_input(
        command_id: "cmd-active-limit-overflow",
        source:,
        target: "https://example.test/active-overflow",
        relation: "references",
        target_kind: "external"
      )
    )
    expect(active_overflow.failure.code).to eq(:development_artifact_relation_limit_reached)
    expect(active_overflow.failure.details).to include(
      limit_kind: "active",
      active_remaining: 0,
      lifetime_remaining: Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_RELATION_LIFETIME_MAXIMUM_COUNT -
        Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_ACTIVE_RELATION_MAXIMUM_COUNT
    )

    replacement = active.first
    (
      Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_RELATION_LIFETIME_MAXIMUM_COUNT -
      Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_ACTIVE_RELATION_MAXIMUM_COUNT
    ).times do |index|
      result = declare_relation.call(
        relation_input(
          command_id: "cmd-lifetime-replacement-#{index}",
          source:,
          target: "https://example.test/replacement-#{index}",
          relation: "references",
          target_kind: "external",
          supersedes: {
            relation_id: replacement.relation_id,
            reason: "replace active edge #{index}"
          }
        )
      )
      expect(result).to be_success
      replacement = result.value!.data
    end

    lifetime_overflow = declare_relation.call(
      relation_input(
        command_id: "cmd-lifetime-limit-overflow",
        source:,
        target: "https://example.test/lifetime-overflow",
        relation: "references",
        target_kind: "external",
        supersedes: {
          relation_id: replacement.relation_id,
          reason: "exceeds lifetime"
        }
      )
    )

    expect(lifetime_overflow.failure.code).to eq(:development_artifact_relation_limit_reached)
    expect(lifetime_overflow.failure.details).to include(
      limit_kind: "lifetime",
      active_remaining: 0,
      lifetime_remaining: 0
    )
    expect(command_events("cmd-active-limit-overflow")).to be_empty
    expect(command_events("cmd-lifetime-limit-overflow")).to be_empty
  end

  def capture_input(
    command_id: "cmd-artifact-capture",
    locator: "docs/readme.md",
    revision: "abc123",
    observed_at: "2026-08-25T16:00:00.000000Z",
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
      content: {
        encoding: "utf-8",
        media_type: "text/markdown",
        text:
      },
      source: {
        kind: "local_file",
        locator:,
        revision:,
        observed_at:,
        collector: "spec/v1"
      }
    }.merge(overrides)
  end

  def classification_input(
    command_id: "cmd-classification-correct",
    observation_id:,
    expected_revision: 1,
    title: "Other title"
  )
    {
      command_id:,
      actor: { kind: "agent", id: "agent-1" },
      observation_id:,
      expected_revision:,
      title:,
      kind: "documentation",
      labels: %w[docs imported],
      reason: "Correct the observation title"
    }
  end

  def relation_input(
    command_id: "cmd-relation",
    source:,
    target:,
    relation: "derived_from",
    target_kind: "artifact",
    attributes: {},
    supersedes: nil
  )
    input = {
      command_id:,
      actor: { kind: "agent", id: "agent-1" },
      source_artifact_id: source,
      relation:,
      target: { kind: target_kind, id: target },
      attributes:
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

  def observation_events(observation_id)
    event_store.read(
      streams.development_artifact_observation(observation_id),
      Coordinator::Write::EventQueries::DEVELOPMENT_ARTIFACT_OBSERVATION_HISTORY
    )
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_COMPLETION)
  end
end
