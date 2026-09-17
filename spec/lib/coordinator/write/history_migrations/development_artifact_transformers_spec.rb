# frozen_string_literal: true

RSpec.describe "history migration Development Artifact transformers", :event_store do
  let(:source_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:target_store) do
    Coordinator::Write::EventStore.new(client: PgEventstore.client(:migration_target))
  end
  let(:registry) { Coordinator::Container["history_migrations.transformer_registry"] }
  let(:planner) { Coordinator::Container["history_migrations.event_planning_dispatcher"] }
  let(:dispatcher) { Coordinator::Container["history_migrations.event_dispatcher"] }
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:legacy_artifact_id) { "artifact:v1:#{'a' * 64}" }
  let(:first_observation_id) { "artifact-observation:v1:#{'b' * 64}" }
  let(:second_observation_id) { "artifact-observation:v1:#{'c' * 64}" }
  let(:content) do
    Coordinator::Write::Content::TextV1.new(
      encoding: "utf-8",
      media_type: "text/markdown",
      text: "legacy documentation\n",
      content_sha256: "sha256:#{'d' * 64}",
      byte_size: 21
    )
  end
  let(:initial_source) do
    Coordinator::Write::DevelopmentArtifacts::SourceV1.new(
      kind: "local_file",
      locator: "docs/README.md",
      revision: "legacy-one",
      observed_at: "2026-08-01T10:00:00.000000Z",
      collector: "legacy-import/v1"
    )
  end
  let(:updated_source) do
    Coordinator::Write::DevelopmentArtifacts::SourceV1.new(
      kind: "git_commit",
      locator: "docs/README.md",
      revision: "legacy-two",
      observed_at: "2026-08-02T10:00:00.000000Z",
      collector: "legacy-git/v1"
    )
  end

  it "migrates legacy digest identities into UUIDv7 property facts with exact observation links" do
    history = persist_history
    upper_position = history.fetch(:corrected).global_position
    history.values.each do |event|
      expect(plan(event, upper_position:)).to be_success
    end

    captured_facts = transform(history.fetch(:captured), upper_position:).value!
    first_observation_facts = transform(history.fetch(:first_observed), upper_position:).value!
    second_observation_facts = transform(history.fetch(:second_observed), upper_position:).value!
    correction_facts = transform(history.fetch(:corrected), upper_position:).value!

    expect(captured_facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::DevelopmentArtifactCreatedV1,
      Coordinator::Write::Events::DevelopmentArtifactScopeChangedV1,
      Coordinator::Write::Events::DevelopmentArtifactTitleChangedV1,
      Coordinator::Write::Events::DevelopmentArtifactKindChangedV1,
      Coordinator::Write::Events::DevelopmentArtifactSourceChangedV1,
      Coordinator::Write::Events::DevelopmentArtifactContentChangedV1,
      Coordinator::Write::Events::DevelopmentArtifactLabelAddedV1,
      Coordinator::Write::Events::DevelopmentArtifactLabelAddedV1
    ])
    target_artifact_id = captured_facts.first.target_stream.stream_id
    expect(target_artifact_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(target_artifact_id).not_to eq(legacy_artifact_id)
    expect(captured_facts.flat_map { _1.event.to_h.keys }).not_to include(:captured_at)
    expect(captured_facts.fetch(4).metadata_extension).to have_attributes(
      collector: "legacy-import/v1"
    )
    expect(captured_facts.fetch(5).metadata_extension).to have_attributes(
      encoding: "utf-8",
      media_type: "text/markdown",
      byte_size: 21,
      content_sha256: "sha256:#{'d' * 64}"
    )

    expect(first_observation_facts.map { _1.event.class }).to eq(
      [ Coordinator::Write::Events::DevelopmentArtifactObservationRecordedV1 ] +
      Array.new(8, Coordinator::Write::Events::DevelopmentArtifactObservationFactLinkedV1)
    )
    expect(second_observation_facts.first(7).map { _1.event.class }).to eq([
      Coordinator::Write::Events::DevelopmentArtifactScopeChangedV1,
      Coordinator::Write::Events::DevelopmentArtifactTitleChangedV1,
      Coordinator::Write::Events::DevelopmentArtifactKindChangedV1,
      Coordinator::Write::Events::DevelopmentArtifactSourceChangedV1,
      Coordinator::Write::Events::DevelopmentArtifactLabelRemovedV1,
      Coordinator::Write::Events::DevelopmentArtifactLabelAddedV1,
      Coordinator::Write::Events::DevelopmentArtifactObservationRecordedV1
    ])
    expect(second_observation_facts.drop(7).map(&:event)).to all(
      be_a(Coordinator::Write::Events::DevelopmentArtifactObservationFactLinkedV1)
    )
    expect(second_observation_facts.fetch(6).metadata_extension).to have_attributes(
      collector: "legacy-git/v1"
    )

    expect(correction_facts.first(5).map { _1.event.class }).to eq([
      Coordinator::Write::Events::DevelopmentArtifactTitleChangedV1,
      Coordinator::Write::Events::DevelopmentArtifactKindChangedV1,
      Coordinator::Write::Events::DevelopmentArtifactLabelRemovedV1,
      Coordinator::Write::Events::DevelopmentArtifactLabelAddedV1,
      Coordinator::Write::Events::DevelopmentArtifactClassificationCorrectionRecordedV1
    ])
    expect(correction_facts.drop(5).map { _1.event.role }).to eq(%w[title kind label label])
    expect(correction_facts.flat_map { _1.event.to_h.keys }).not_to include(:corrected_at)

    history.values.each do |event|
      expect(dispatch(event, upper_position:)).to be_success
    end

    artifact_events = target_events(captured_facts.first.target_stream, maximum_count: 18)
    first_observation_events = target_events(
      first_observation_facts.first.target_stream,
      maximum_count: 9
    )
    second_observation_events = target_events(
      second_observation_facts.fetch(6).target_stream,
      maximum_count: 14
    )

    expect(artifact_events.map(&:stream_revision)).to eq((0..17).to_a)
    expect(first_observation_events.map(&:stream_revision)).to eq((0..8).to_a)
    expect(second_observation_events.map(&:stream_revision)).to eq((0..13).to_a)
    expect(artifact_events.flat_map { _1.data.keys }).not_to include(
      "captured_at", "recorded_at", "corrected_at"
    )
    expect(artifact_events.fetch(4).metadata).to include("collector" => "legacy-import/v1")
    expect(artifact_events.fetch(5).metadata).to include(
      "encoding" => "utf-8",
      "media_type" => "text/markdown",
      "byte_size" => 21,
      "content_sha256" => "sha256:#{'d' * 64}"
    )

    expect(observed_references(first_observation_events)).to eq(
      artifact_events.first(8).map(&:id)
    )
    expect(observed_references(second_observation_events.first(9))).to eq(
      current_property_events(artifact_events.first(14)).map(&:id)
    )
    expect(observed_references(second_observation_events.last(4))).to eq(
      artifact_events.last(4).map(&:id)
    )

    state = Coordinator::Write::DevelopmentArtifacts::Loader.new(event_store: target_store).load(
      target_artifact_id
    )
    expect(state.created.artifact_id).to eq(target_artifact_id)
    expect(state.scope.scope).to eq("project:modern")
    expect(state.title.title).to eq("README reviewed")
    expect(state.kind.kind).to eq("documentation")
    expect(state.labels).to contain_exactly("current", "reviewed")
    expect(state.source).to have_attributes(
      source_kind: "git_commit",
      locator: "docs/README.md",
      revision: "legacy-two"
    )
    expect(state.source_collector).to eq("legacy-git/v1")
    expect(state.content.content).to eq("legacy documentation\n")
    expect(state.content_metadata).to have_attributes(
      encoding: "utf-8",
      media_type: "text/markdown",
      byte_size: 21,
      content_sha256: "sha256:#{'d' * 64}"
    )
  end

  it "moves relation declarations and supersessions into UUIDv7 relation streams" do
    target_artifact_ids = [
      "artifact:v1:#{'e' * 64}",
      "artifact:v1:#{'f' * 64}"
    ]
    relation_ids = [
      "artifact-relation:v1:#{'1' * 64}",
      "artifact-relation:v1:#{'2' * 64}"
    ]
    source_capture = persist_artifact_capture(legacy_artifact_id, title: "Source Artifact")
    target_captures = target_artifact_ids.each_with_index.map do |artifact_id, index|
      persist_artifact_capture(artifact_id, title: "Target Artifact #{index + 1}")
    end
    declarations = relation_ids.each_with_index.map do |relation_id, index|
      persist_relation_declaration(
        relation_id:,
        target_artifact_id: target_artifact_ids.fetch(index),
        path: "references/#{index + 1}.md"
      )
    end
    supersession = persist_relation_supersession(
      superseded_relation_id: relation_ids.fetch(0),
      replacement_relation_id: relation_ids.fetch(1)
    )
    upper_position = supersession.global_position

    source_artifact_id = transform(source_capture, upper_position:).value!.first.target_stream.stream_id
    target_artifact_ids = target_captures.map do |event|
      transform(event, upper_position:).value!.first.target_stream.stream_id
    end
    relation_facts = declarations.map { transform(_1, upper_position:).value!.sole }
    supersession_fact = transform(supersession, upper_position:).value!.sole

    expect(relation_facts.map { _1.target_stream.stream_id }).to all(
      match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    )
    expect(relation_facts.map { _1.target_stream.stream_id }.uniq.length).to eq(2)
    expect(relation_facts.map { _1.event.source_artifact_id }).to eq(
      [ source_artifact_id, source_artifact_id ]
    )
    expect(relation_facts.map { _1.event.target_id }).to eq(target_artifact_ids)
    expect(supersession_fact.target_stream).to eq(relation_facts.fetch(0).target_stream)
    expect(supersession_fact.event).to have_attributes(
      relation_id: relation_facts.fetch(0).target_stream.stream_id,
      source_artifact_id:,
      replacement_relation_id: relation_facts.fetch(1).target_stream.stream_id,
      reason: "Replace the stale reference"
    )
    expect(
      relation_facts.flat_map { _1.event.to_h.keys } + supersession_fact.event.to_h.keys
    ).not_to include(:declared_at, :superseded_at)
    expect((relation_facts + [ supersession_fact ]).flat_map(&:markers).join("\n")).not_to match(
      /artifact(?:-relation)?:v1:/
    )

    [ *declarations, supersession ].each do |event|
      expect(plan(event, upper_position:)).to be_success
    end
    [ *declarations, supersession ].each do |event|
      expect(dispatch(event, upper_position:)).to be_success
    end

    superseded_events = target_events(relation_facts.fetch(0).target_stream, maximum_count: 2)
    replacement_events = target_events(relation_facts.fetch(1).target_stream, maximum_count: 1)
    expect(superseded_events.map(&:type)).to eq(
      %w[DevelopmentArtifactRelationDeclared DevelopmentArtifactRelationSuperseded]
    )
    expect(superseded_events.map(&:stream_revision)).to eq([ 0, 1 ])
    expect(replacement_events.map(&:type)).to eq([ "DevelopmentArtifactRelationDeclared" ])
    expect(replacement_events.sole.stream_revision).to eq(0)
    expect(superseded_events.flat_map { _1.data.keys }).not_to include("declared_at", "superseded_at")

    state = Coordinator::Write::Domain::DevelopmentArtifacts::RelationStateV2.reduce(
      superseded_events.map { load_target_event(_1) }
    )
    expect(state).not_to be_active
    expect(state.declaration.target_id).to eq(target_artifact_ids.fetch(0))
    expect(state.supersession.replacement_relation_id).to eq(
      relation_facts.fetch(1).target_stream.stream_id
    )
  end

  it "preserves an external target without treating it as an internal stream identity" do
    persist_artifact_capture(legacy_artifact_id, title: "Source Artifact")
    source_event = persist_relation_declaration(
      relation_id: "artifact-relation:v1:#{'3' * 64}",
      target: Coordinator::Write::DevelopmentArtifacts::RelationTargetV1.new(
        kind: "external",
        id: "https://example.test/reference",
        status: "unverified"
      ),
      path: "reference"
    )

    fact = transform(source_event, upper_position: source_event.global_position).value!.sole

    expect(fact.event).to have_attributes(
      target_kind: "external",
      target_id: "https://example.test/reference"
    )
    expect(fact.target_stream.stream_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
  end

  def persist_history
    artifact = Coordinator::Write::HistoryMigrations::LegacyDevelopmentArtifacts::ArtifactV2.new(
      artifact_id: legacy_artifact_id,
      scope: "project:legacy",
      title: "README legacy",
      kind: "documentation",
      labels: %w[docs imported],
      content:,
      source: initial_source
    )
    captured = persist(
      stream("DevelopmentMemory", "DevelopmentArtifact", legacy_artifact_id),
      Coordinator::Write::HistoryMigrations::LegacyEvents::DevelopmentArtifactCapturedV2.new(
        artifact:,
        captured_at: "2026-08-01T10:00:01.000000Z"
      )
    )
    first_observed = persist_observation(
      first_observation_id,
      scope: "project:legacy",
      title: "README legacy",
      kind: "documentation",
      labels: %w[docs imported],
      source: initial_source
    )
    second_observed = persist_observation(
      second_observation_id,
      scope: "project:modern",
      title: "README current",
      kind: "web_research",
      labels: %w[current docs],
      source: updated_source
    )
    corrected = persist(
      stream("DevelopmentMemory", "DevelopmentArtifactObservation", second_observation_id),
      Coordinator::Write::HistoryMigrations::LegacyEvents::DevelopmentArtifactClassificationCorrectedV1.new(
        observation_id: second_observation_id,
        artifact_id: legacy_artifact_id,
        classification_revision: 2,
        title: "README reviewed",
        kind: "documentation",
        labels: %w[current reviewed],
        reason: "Correct the imported classification",
        corrected_at: "2026-08-02T10:01:00.000000Z"
      )
    )
    { captured:, first_observed:, second_observed:, corrected: }
  end

  def persist_observation(observation_id, scope:, title:, kind:, labels:, source:)
    observation =
      Coordinator::Write::HistoryMigrations::LegacyDevelopmentArtifacts::ArtifactObservationV1.new(
        observation_id:,
        artifact_id: legacy_artifact_id,
        scope:,
        title:,
        kind:,
        labels:,
        source:
      )
    persist(
      stream("DevelopmentMemory", "DevelopmentArtifactObservation", observation_id),
      Coordinator::Write::HistoryMigrations::LegacyEvents::DevelopmentArtifactObservedV1.new(
        observation:,
        recorded_at: source.observed_at
      )
    )
  end

  def persist(target_stream, payload, markers: artifact_markers(target_stream))
    source_store.append(
      target_stream,
      [
        PgEventstore::Event.new(
          id: SecureRandom.uuid_v7,
          type: payload.class.event_type,
          data: payload.to_h,
          metadata: {
            "schema_version" => payload.class.schema_version,
            "command_id" => SecureRandom.uuid_v7,
            "actor_kind" => "agent",
            "actor_id" => "legacy-agent",
            "recorded_by" => "coordinator",
            "policy_version" => "development-artifact-repository/v1"
          },
          markers:,
          correlation_id: SecureRandom.uuid_v7
        )
      ]
    ).sole
  end

  def persist_artifact_capture(artifact_id, title:)
    artifact = Coordinator::Write::HistoryMigrations::LegacyDevelopmentArtifacts::ArtifactV2.new(
      artifact_id:,
      scope: "project:legacy",
      title:,
      kind: "documentation",
      labels: [],
      content:,
      source: initial_source
    )
    persist(
      stream("DevelopmentMemory", "DevelopmentArtifact", artifact_id),
      Coordinator::Write::HistoryMigrations::LegacyEvents::DevelopmentArtifactCapturedV2.new(
        artifact:,
        captured_at: "2026-08-01T10:00:01.000000Z"
      ),
      markers: [ "development-artifact:#{artifact_id}" ]
    )
  end

  def persist_relation_declaration(relation_id:, path:, target_artifact_id: nil, target: nil)
    target ||= Coordinator::Write::DevelopmentArtifacts::RelationTargetV1.new(
      kind: "artifact",
      id: target_artifact_id,
      status: "verified"
    )
    relation = Coordinator::Write::HistoryMigrations::LegacyDevelopmentArtifacts::RelationV1.new(
      relation_id:,
      source_artifact_id: legacy_artifact_id,
      relation: "references",
      target:,
      attributes: Coordinator::Write::DevelopmentArtifacts::RelationAttributesV1.new(path:)
    )
    persist(
      stream("DevelopmentMemory", "DevelopmentArtifact", legacy_artifact_id),
      Coordinator::Write::HistoryMigrations::LegacyEvents::DevelopmentArtifactRelationDeclaredV1.new(
        artifact_relation: relation,
        declared_at: "2026-08-01T10:01:00.000000Z"
      ),
      markers: [
        "development-artifact:#{legacy_artifact_id}",
        "development-artifact-relation:#{relation_id}"
      ]
    )
  end

  def persist_relation_supersession(superseded_relation_id:, replacement_relation_id:)
    persist(
      stream("DevelopmentMemory", "DevelopmentArtifact", legacy_artifact_id),
      Coordinator::Write::HistoryMigrations::LegacyEvents::DevelopmentArtifactRelationSupersededV1.new(
        source_artifact_id: legacy_artifact_id,
        superseded_relation_id:,
        replacement_relation_id:,
        reason: "Replace the stale reference",
        superseded_at: "2026-08-01T10:02:00.000000Z"
      ),
      markers: [
        "development-artifact:#{legacy_artifact_id}",
        "development-artifact-relation:#{superseded_relation_id}",
        "development-artifact-relation:#{replacement_relation_id}"
      ]
    )
  end

  def artifact_markers(target_stream)
    markers = [ "development-artifact:#{legacy_artifact_id}" ]
    if target_stream.stream_name == "DevelopmentArtifactObservation"
      markers << "development-artifact-observation:#{target_stream.stream_id}"
    end
    markers
  end

  def transform(source_event, upper_position:)
    registry.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event:
    )
  end

  def plan(source_event, upper_position:)
    planner.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event:
    )
  end

  def dispatch(source_event, upper_position:)
    HistoryMigrationWaveDispatch.call(
      dispatcher:,
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event:
    )
  end

  def target_events(target_stream, maximum_count:)
    target_store.read(
      target_stream,
      Coordinator::Write::EventReadCriteria.new(
        event_types: Coordinator::Write::EventSchemaRegistry::DEFAULT_DEFINITIONS.keys.map(&:first).uniq,
        maximum_count:,
        direction: :asc
      )
    )
  end

  def load_target_event(event)
    Coordinator::Write::EventSchemaRegistry.new.load(
      type: event.type,
      schema_version: event.metadata.fetch("schema_version"),
      data: event.data
    )
  end

  def observed_references(events)
    events.filter_map do |event|
      event.data.dig("observed_fact", "event_id") if event.type == "DevelopmentArtifactObservationFactLinked"
    end
  end

  def current_property_events(events)
    roles = {
      "DevelopmentArtifactCreated" => "created",
      "DevelopmentArtifactScopeChanged" => "scope",
      "DevelopmentArtifactTitleChanged" => "title",
      "DevelopmentArtifactKindChanged" => "kind",
      "DevelopmentArtifactSourceChanged" => "source",
      "DevelopmentArtifactContentChanged" => "content"
    }
    current = {}
    labels = {}
    events.each do |event|
      role = roles[event.type]
      current[role] = event if role
      labels[event.data.fetch("label")] = event if event.type == "DevelopmentArtifactLabelAdded"
      labels.delete(event.data.fetch("label")) if event.type == "DevelopmentArtifactLabelRemoved"
    end
    [
      *current.values_at("created", "scope", "title", "kind", "source", "content"),
      *labels.sort_by { _1.first.b }.map(&:last)
    ]
  end

  def stream(context, stream_name, stream_id)
    Coordinator::Write::StreamReference.new(context:, stream_name:, stream_id:)
  end
end
