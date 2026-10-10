# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::DevelopmentArtifactsV1, :read_model, :event_store do
  subject(:projector) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }

  let(:repository) { Coordinator::Read::Repositories::DevelopmentArtifacts.new }
  let(:correlation_id) { SecureRandom.uuid_v7 }

  it "keeps event attribution while a granular observation is still incomplete" do
    observation_id = SecureRandom.uuid_v7
    event = observation_stream_event(
      Coordinator::Write::Events::DevelopmentArtifactObservationRecordedV1.new(observation_id:),
      observation_id:,
      revision: 0,
      position: 9
    )

    projector.call(event)

    expect(Coordinator::Read::DevelopmentArtifactObservation.find(observation_id)).to have_attributes(
      observed_actor: {
        "kind" => "agent",
        "id" => "agent-projector",
        "authenticated" => false
      },
      observed_event: include("event_id" => event.id),
      observed_at_domain: event.created_at
    )
  end

  it "derives v2 relation target status from the target kind" do
    source_id = SecureRandom.uuid_v7
    artifact_relation_id = SecureRandom.uuid_v7
    external_relation_id = SecureRandom.uuid_v7
    stream_factory = Coordinator::Write::StreamFactory.new
    artifact_relation = Coordinator::Write::Events::DevelopmentArtifactRelationDeclaredV2.new(
      relation_id: artifact_relation_id,
      source_artifact_id: source_id,
      relation: "references",
      target_kind: "artifact",
      target_id: SecureRandom.uuid_v7,
      path: nil,
      fragment: nil,
      normalized_locator: nil
    )
    external_relation = Coordinator::Write::Events::DevelopmentArtifactRelationDeclaredV2.new(
      relation_id: external_relation_id,
      source_artifact_id: source_id,
      relation: "references",
      target_kind: "external",
      target_id: "https://example.test/resource",
      path: nil,
      fragment: nil,
      normalized_locator: nil
    )

    projector.call(
      ProjectionEventFactory.build(
        payload: artifact_relation,
        stream: stream_factory.development_artifact_relation(artifact_relation_id),
        stream_revision: 0,
        global_position: 10,
        policy_version: "development-artifact-repository/v2"
      )
    )
    projector.call(
      ProjectionEventFactory.build(
        payload: external_relation,
        stream: stream_factory.development_artifact_relation(external_relation_id),
        stream_revision: 0,
        global_position: 11,
        policy_version: "development-artifact-repository/v2"
      )
    )

    expect(Coordinator::Read::DevelopmentArtifactRelation.find(artifact_relation_id)).to have_attributes(
      target_status: "verified",
      target_name: nil,
      target_scope: nil
    )
    expect(Coordinator::Read::DevelopmentArtifactRelation.find(external_relation_id)).to have_attributes(
      target_status: "unverified",
      target_name: nil,
      target_scope: nil
    )
  end

  it "projects granular capture and delayed peer delivery idempotently with exact evidence" do
    source, observation = build_artifact(locator: "evidence.md", text: "evidence\n")
    target, = build_artifact(locator: "target.bin", binary: true)
    facts, observations = observation_facts(source, observation)
    declaration = relation_payload(source: source.artifact_id, target: target.artifact_id)
    relation = relation_event(declaration, revision: 0, position: 300)

    projector.call(relation)
    projector.call(relation)
    expect(repository.fetch(source.artifact_id)).to be_nil
    expect(Coordinator::Read::DevelopmentArtifactRelation.count).to eq(1)
    lagging = relation_query.call(artifact_id: source.artifact_id, direction: "outgoing", limit: 10).value!
    expect(lagging.data.page).to have_attributes(artifact: nil)
    expect(lagging.data.page.items.sole).to have_attributes(peer_artifact: nil)
    expect(lagging.warnings.sole).to include("not yet observed")

    (facts + observations).each { |event| 2.times { projector.call(event) } }
    view = repository.fetch(source.artifact_id)
    created = facts.first
    expect(view.artifact).to have_attributes(
      artifact_id: source.artifact_id,
      title: "Captured evidence",
      relationship_count: 1,
      relationship_capacity: have_attributes(active_count: 1, active_limit: 128, lifetime_count: 1, lifetime_limit: 256),
      captured: have_attributes(
        event: have_attributes(event_id: created.id, stream_revision: 0),
        global_position: created.global_position,
        causation_id: created.causation_id,
        correlation_id: created.correlation_id
      )
    )
    expect(view.relationships.sole).to have_attributes(
      relation_id: declaration.relation_id,
      relation: "derived_from",
      inverse_relation: "source_of",
      target: have_attributes(kind: "artifact", id: target.artifact_id, status: "verified"),
      peer_artifact: nil,
      follow_action: have_attributes(
        tool: "development_artifact_get",
        arguments: have_attributes(artifact_id: target.artifact_id)
      )
    )
    expect(processed_events.count).to eq(facts.length + observations.length + 1)
    expect(view.to_h.keys & %i[fresh pending projection_status]).to be_empty
    expect(Coordinator::Read::DevelopmentArtifactObservation.find(observation.observation_id).updated_at)
      .to eq(observations.last.created_at)
  end

  it "round-trips UTF-8 and binary content through immutable observation links" do
    text, text_observation = build_artifact(locator: "evidence.md", text: "evidence\n")
    binary, binary_observation = build_artifact(locator: "profile.bin", binary: true)
    [ [ text, text_observation ], [ binary, binary_observation ] ].each do |artifact, observation|
      facts, links = observation_facts(artifact, observation)
      (facts + links).each { projector.call(_1) }
    end

    expect(repository.fetch_content(text.artifact_id)).to have_attributes(text: "evidence\n", encoding: "utf-8")
    expect(repository.fetch_content(binary.artifact_id)).to have_attributes(base64: "AP8=", encoding: "binary")
    expect(repository.fetch_content(text.artifact_id, observation_id: text_observation.observation_id))
      .to have_attributes(text: "evidence\n")
    expect(repository.fetch_content(binary.artifact_id, observation_id: binary_observation.observation_id))
      .to have_attributes(base64: "AP8=")
    expect(repository.fetch(text.artifact_id).to_h.to_s).not_to include("evidence\\n")
  end

  it "keeps supersession evidence while the replacement stream has not been projected" do
    source_id = SecureRandom.uuid_v7
    old_payload = relation_payload(source: source_id, target: SecureRandom.uuid_v7)
    replacement = relation_payload(source: source_id, target: SecureRandom.uuid_v7)
    declaration = relation_event(old_payload, revision: 0, position: 200)
    supersession = relation_event(
      Coordinator::Write::Events::DevelopmentArtifactRelationSupersededV2.new(
        relation_id: old_payload.relation_id,
        source_artifact_id: source_id,
        replacement_relation_id: replacement.relation_id,
        reason: "wrong target"
      ),
      revision: 1,
      position: 300
    )

    [ declaration, supersession, supersession ].each { projector.call(_1) }
    expect(Coordinator::Read::DevelopmentArtifactRelationSupersession.count).to eq(1)
    projector.call(relation_event(replacement, revision: 0, position: 400))
    page = relation_query.call(artifact_id: source_id, direction: "outgoing", include_superseded: true, limit: 10).value!.data.page
    expect(page.items.map(&:status)).to contain_exactly("active", "superseded")
    expect(page.items.find { _1.status == "superseded" }).to have_attributes(
      relation_id: old_payload.relation_id,
      replacement_relation_id: replacement.relation_id,
      supersession_reason: "wrong target",
      superseded: have_attributes(event: have_attributes(event_id: supersession.id), occurred_at: supersession.created_at.utc.iso8601(6))
    )
    active = relation_query.call(artifact_id: source_id, direction: "outgoing", limit: 10).value!.data.page
    expect(active.items.map(&:status)).to eq([ "active" ])
  end

  it "preserves older observations while new facts and classification links update current state" do
    first, first_observation = build_artifact(locator: "same.md", revision: "commit-a", text: "same bytes\n")
    second, second_observation = build_artifact(
      locator: "same.md", revision: "commit-b", text: "same bytes\n", artifact_id: first.artifact_id
    )
    [ [ first, first_observation ], [ second, second_observation ] ].each do |artifact, observation|
      facts, links = observation_facts(artifact, observation)
      (facts + links).each { projector.call(_1) }
    end
    events = Coordinator::Write::Events
    artifact_id = second.artifact_id
    properties = append_facts(streams.development_artifact(artifact_id), [
      events::DevelopmentArtifactTitleChangedV1.new(artifact_id:, title: "Corrected title"),
      events::DevelopmentArtifactLabelRemovedV1.new(artifact_id:, label: "evidence"),
      events::DevelopmentArtifactLabelAddedV1.new(artifact_id:, label: "corrected")
    ])
    correction = append_facts(streams.development_artifact_observation(second_observation.observation_id), [
      events::DevelopmentArtifactClassificationCorrectionRecordedV1.new(
        artifact_id:, observation_id: second_observation.observation_id,
        classification_revision: 2, reason: "Correct imported classification"
      )
    ]).sole
    links = link_facts(properties, second_observation.observation_id, artifact_id)
    (properties + [ correction ] + links).each { |event| 2.times { projector.call(event) } }

    first_view = repository.fetch(first.artifact_id, observation_id: first_observation.observation_id)
    corrected_view = repository.fetch(second.artifact_id, observation_id: second_observation.observation_id)
    expect(first_view.artifact).to have_attributes(
      title: "Captured evidence", classification_revision: 1, source: have_attributes(revision: "commit-a")
    )
    expect(corrected_view.artifact).to have_attributes(
      title: "Corrected title", labels: %w[corrected docs],
      classification_revision: 2, classification_reason: "Correct imported classification",
      source: have_attributes(revision: "commit-b"),
      observed: have_attributes(event: have_attributes(type: "DevelopmentArtifactObservationRecorded")),
      classified: have_attributes(event: have_attributes(type: "DevelopmentArtifactClassificationCorrectionRecorded"))
    )
    old = search_items("development_artifact.title", "Captured evidence").sole
    expect(old.document_id).to eq("observation:#{first_observation.observation_id}")
    current = search_items("development_artifact.title", "Corrected title").sole
    expect(current.document_id).to eq("current:#{artifact_id}")
    classified = search_items("development_artifact.classification_reason", "Correct imported classification").sole
    expect(classified.document_id).to eq(current.document_id)
    expect(classified.updated_at).to eq(Coordinator::Read::DevelopmentArtifactObservation.find(second_observation.observation_id).updated_at.utc.iso8601(6))
    expect(classified.retrieval_actions.first.arguments.observation_id).to eq(second_observation.observation_id)
  end

  it "rejects superseded relation schema before claiming or writing a projection" do
    payload = relation_payload(source: SecureRandom.uuid_v7, target: SecureRandom.uuid_v7)
    event = relation_event(payload, revision: 0, position: 1)
    event.metadata = event.metadata.merge("schema_version" => 1)
    expect { projector.call(event) }.to raise_error(Coordinator::Read::InvalidProjectionSource)
    expect(processed_events.count).to eq(0)
    expect(Coordinator::Read::DevelopmentArtifactRelation.count).to eq(0)
  end

  def build_artifact(
    locator:,
    text: nil,
    binary: false,
    revision: nil,
    observed_at: "2026-08-30T12:00:00.000000Z",
    artifact_id: nil
  )
    content_input = binary ?
      { encoding: "binary", media_type: "application/octet-stream", base64: "AP8=" } :
      { encoding: "utf-8", media_type: "text/markdown", text: }
    content = Coordinator::Write::DevelopmentArtifacts::ContentBuilder.new.call(content_input).value!
    source = Coordinator::Write::DevelopmentArtifacts::SourceV1.new(
      kind: "local_file",
      locator:,
      revision:,
      observed_at:,
      collector: "spec/v1"
    )
    artifact = Coordinator::Write::DevelopmentArtifacts::ArtifactBuilder.new.call(
      scope: "project:alpha",
      title: "Captured evidence",
      kind: binary ? "performance_profile" : "documentation",
      labels: binary ? %w[binary profile] : %w[docs evidence],
      content:,
      source:
    )
    if artifact_id
      artifact = Coordinator::Write::DevelopmentArtifacts::ArtifactV2.new(
        artifact.to_h.merge(artifact_id:)
      )
    end
    observation = Coordinator::Write::DevelopmentArtifacts::ObservationBuilder.new.call(artifact:)
    [ artifact, observation ]
  end

  def search_items(field, value)
    codec = Coordinator::Read::Search::CursorCodec.new(secret: "artifact-projector-search")
    query = Coordinator::Read::Search::QueryBuilder.new(cursor_codec: codec).call(
      fields: [ { field:, query: { match: "contains", value: } } ]
    ).value!
    Coordinator::Read::Repositories::DevelopmentSearch.new(cursor_codec: codec).page(query).value!.items
  end

  def observation_facts(artifact, observation)
    events = Coordinator::Write::Events
    artifact_id = artifact.artifact_id
    @initial_artifact_facts ||= {}
    fresh = !@initial_artifact_facts.key?(artifact_id)
    properties = [
      events::DevelopmentArtifactScopeChangedV1.new(artifact_id:, scope: artifact.scope),
      events::DevelopmentArtifactTitleChangedV1.new(artifact_id:, title: artifact.title),
      events::DevelopmentArtifactKindChangedV1.new(artifact_id:, kind: artifact.kind),
      *artifact.labels.map { events::DevelopmentArtifactLabelAddedV1.new(artifact_id:, label: _1) },
      events::DevelopmentArtifactSourceChangedV1.new(
        artifact_id:, source_kind: artifact.source.kind, locator: artifact.source.locator,
        revision: artifact.source.revision, observed_at: artifact.source.observed_at
      ),
      events::DevelopmentArtifactContentChangedV1.new(
        artifact_id:, content: artifact.content.respond_to?(:text) ? artifact.content.text : artifact.content.base64
      )
    ]
    properties.unshift(events::DevelopmentArtifactCreatedV1.new(artifact_id:)) if fresh
    persisted = append_facts(streams.development_artifact(artifact_id), properties, artifact:)
    @initial_artifact_facts[artifact_id] = persisted.first if fresh
    recorded = append_facts(streams.development_artifact_observation(observation.observation_id), [
      events::DevelopmentArtifactObservationRecordedV1.new(observation_id: observation.observation_id)
    ])
    observed_facts = fresh ? persisted : [ @initial_artifact_facts.fetch(artifact_id), *persisted ]
    [ persisted, recorded + link_facts(observed_facts, observation.observation_id, artifact_id) ]
  end

  def link_facts(facts, observation_id, artifact_id)
    roles = {
      "DevelopmentArtifactCreated" => "created", "DevelopmentArtifactScopeChanged" => "scope",
      "DevelopmentArtifactTitleChanged" => "title", "DevelopmentArtifactKindChanged" => "kind",
      "DevelopmentArtifactLabelAdded" => "label", "DevelopmentArtifactLabelRemoved" => "label",
      "DevelopmentArtifactSourceChanged" => "source", "DevelopmentArtifactContentChanged" => "content"
    }
    payloads = facts.map do |fact|
      Coordinator::Write::Events::DevelopmentArtifactObservationFactLinkedV1.new(
        artifact_id:, observation_id:, role: roles.fetch(fact.type),
        observed_fact: Coordinator::Write::EventReference.new(
          event_id: fact.id, type: fact.type, stream_context: fact.stream.context,
          stream_name: fact.stream.stream_name, stream_id: fact.stream.stream_id,
          stream_revision: fact.stream_revision
        )
      )
    end
    append_facts(streams.development_artifact_observation(observation_id), payloads)
  end

  def append_facts(stream, payloads, artifact: nil)
    metadata = Coordinator::Write::EventMetadata.new(
      command_id: "cmd-artifact-projector", actor_kind: "agent", actor_id: "agent-projector",
      recorded_by: "coordinator", policy_version: "development-artifact-repository/v1"
    )
    factory = Coordinator::Write::EventFactory.new
    persisted = payloads.map do |payload|
      attributes = metadata
      if payload.is_a?(Coordinator::Write::Events::DevelopmentArtifactContentChangedV1)
        attributes = Coordinator::Write::Metadata::ContentV1.new(
          **metadata.to_h, encoding: artifact.content.encoding, media_type: artifact.content.media_type,
          byte_size: artifact.content.byte_size, content_sha256: artifact.content.content_sha256
        )
      elsif payload.is_a?(Coordinator::Write::Events::DevelopmentArtifactSourceChangedV1)
        attributes = Coordinator::Write::Metadata::CollectorV1.new(**metadata.to_h, collector: artifact.source.collector)
      end
      factory.build!(event: payload, event_id: SecureRandom.uuid_v7, metadata: attributes, markers: [], correlation_id:)
    end
    event_store.append(stream, persisted)
  end

  def relation_payload(source:, target:)
    Coordinator::Write::Events::DevelopmentArtifactRelationDeclaredV2.new(
      relation_id: SecureRandom.uuid_v7, source_artifact_id: source, relation: "derived_from",
      target_kind: "artifact", target_id: target, path: nil, fragment: nil, normalized_locator: nil
    )
  end

  def relation_event(payload, revision:, position:)
    projection_event(
      payload:, stream: streams.development_artifact_relation(payload.relation_id),
      revision:, position:, markers: [ "development-artifact-relation:#{payload.relation_id}" ]
    )
  end

  def observation_stream_event(payload, observation_id:, revision:, position:)
    projection_event(
      payload:, stream: streams.development_artifact_observation(observation_id),
      revision:, position:, markers: [ "development-artifact-observation:#{observation_id}" ]
    )
  end

  def projection_event(payload:, stream:, revision:, position:, markers:)
    ProjectionEventFactory.build(
      payload:, stream:, stream_revision: revision, global_position: position,
      command_id: "cmd-artifact-projector-#{position}", policy_version: "development-artifact-repository/v1",
      actor_id: "agent-projector", correlation_id:, markers:
    )
  end

  def processed_events
    Coordinator::Read::ProcessedProjectionEvent.where(projection_name: "development-artifacts", projection_version: 5)
  end

  def relation_query
    Coordinator::Read::Queries::DevelopmentArtifactRelationList.new
  end
end
