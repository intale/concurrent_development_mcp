# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::DevelopmentArtifactsV1, :read_model do
  subject(:projector) { described_class.new }

  let(:repository) { Coordinator::Read::Repositories::DevelopmentArtifacts.new }
  let(:correlation_id) { SecureRandom.uuid_v7 }

  it "projects capture and delayed relation delivery idempotently with exact source evidence" do
    source, observation = build_artifact(locator: "evidence.md", text: "evidence\n")
    target, = build_artifact(locator: "target.bin", binary: true)
    capture = capture_event(source, position: 100)
    observed = observation_event(observation, position: 200)
    relation = relation_event(
      relation_payload(source: source.artifact_id, target: target.artifact_id),
      revision: 1,
      position: 300
    )

    projector.call(relation)
    projector.call(relation)
    expect(repository.fetch(source.artifact_id)).to be_nil
    expect(Coordinator::Read::DevelopmentArtifactRelation.count).to eq(1)
    lagging = relation_query.call(
      artifact_id: source.artifact_id,
      direction: "outgoing",
      limit: 10
    ).value!
    expect(lagging.data.page).to have_attributes(artifact: nil)
    expect(lagging.data.page.items.sole).to have_attributes(peer_artifact: nil)
    expect(lagging.warnings.sole).to include("not yet observed")

    [ capture, capture, observed, observed ].each { projector.call(_1) }
    view = repository.fetch(source.artifact_id)
    expect(view.artifact).to have_attributes(
      artifact_id: source.artifact_id,
      title: "Captured evidence",
      relationship_count: 1,
      relationship_capacity: have_attributes(
        active_count: 1,
        active_limit: 128,
        active_remaining: 127,
        lifetime_count: 1,
        lifetime_limit: 256,
        lifetime_remaining: 255
      ),
      captured: have_attributes(
        event: have_attributes(event_id: capture.id, stream_revision: 0),
        global_position: capture.global_position,
        causation_id: capture.causation_id,
        correlation_id: capture.correlation_id
      )
    )
    expect(view.relationships.sole).to have_attributes(
      relation_id: relation.data.dig("artifact_relation", "relation_id"),
      relation: "derived_from",
      display_relation: "derived_from",
      inverse_relation: "source_of",
      transitive: true,
      supersedable: true,
      target: have_attributes(kind: "artifact", id: target.artifact_id, status: "verified"),
      peer_artifact: nil,
      follow_action: have_attributes(
        tool: "development_artifact_get",
        arguments: have_attributes(artifact_id: target.artifact_id)
      )
    )
    expect(processed_events.count).to eq(3)
    expect(view.to_h.keys & %i[fresh pending projection_status]).to be_empty
  end

  it "round-trips UTF-8 and binary content without embedding bytes in metadata" do
    text, text_observation = build_artifact(locator: "evidence.md", text: "evidence\n")
    binary, binary_observation = build_artifact(locator: "profile.bin", binary: true)

    [
      capture_event(text, position: 100),
      observation_event(text_observation, position: 200),
      capture_event(binary, position: 300),
      observation_event(binary_observation, position: 400)
    ].each { projector.call(_1) }

    text_content = repository.fetch_content(text.artifact_id)
    binary_content = repository.fetch_content(binary.artifact_id)
    expect(text_content).to have_attributes(text: "evidence\n", encoding: "utf-8")
    expect(text_content.to_h).not_to have_key(:base64)
    expect(binary_content).to have_attributes(base64: "AP8=", encoding: "binary")
    expect(binary_content.to_h).not_to have_key(:text)
    expect(repository.fetch(text.artifact_id).to_h.to_s).not_to include("evidence\\n")
  end

  it "projects an out-of-order supersession without hiding immutable declaration history" do
    source, = build_artifact(locator: "source.md", text: "source\n")
    old_target, = build_artifact(locator: "old.md", text: "old\n")
    new_target, = build_artifact(locator: "new.md", text: "new\n")
    old_payload = relation_payload(source: source.artifact_id, target: old_target.artifact_id)
    new_payload = relation_payload(source: source.artifact_id, target: new_target.artifact_id)
    old_declaration = relation_event(old_payload, revision: 1, position: 200)
    new_declaration = relation_event(new_payload, revision: 3, position: 400)
    supersession = relation_event(
      Coordinator::Write::Events::DevelopmentArtifactRelationSupersededV1.new(
        source_artifact_id: source.artifact_id,
        superseded_relation_id: old_payload.artifact_relation.relation_id,
        replacement_relation_id: new_payload.artifact_relation.relation_id,
        reason: "wrong target",
        superseded_at: "2026-08-30T12:02:00.000000Z"
      ),
      revision: 2,
      position: 300
    )

    projector.call(supersession)
    projector.call(supersession)
    expect(Coordinator::Read::DevelopmentArtifactRelationSupersession.count).to eq(1)
    projector.call(new_declaration)
    projector.call(old_declaration)
    projector.call(capture_event(source, position: 100))

    page = relation_query.call(
      artifact_id: source.artifact_id,
      direction: "outgoing",
      include_superseded: true,
      limit: 10
    ).value!.data.page
    expect(page.items.map(&:status)).to contain_exactly("active", "superseded")
    superseded = page.items.find { _1.status == "superseded" }
    expect(superseded).to have_attributes(
      relation_id: old_payload.artifact_relation.relation_id,
      replacement_relation_id: new_payload.artifact_relation.relation_id,
      supersession_reason: "wrong target",
      superseded: have_attributes(event: have_attributes(type: "DevelopmentArtifactRelationSuperseded"))
    )
    active = relation_query.call(
      artifact_id: source.artifact_id,
      direction: "outgoing",
      limit: 10
    ).value!.data.page
    expect(active.items.map(&:status)).to eq([ "active" ])
  end

  it "converges immutable observations and a classification correction delivered out of order" do
    first, first_observation = build_artifact(
      locator: "same.md",
      revision: "commit-a",
      text: "same bytes\n"
    )
    second, second_observation = build_artifact(
      locator: "same.md",
      revision: "commit-b",
      observed_at: "2026-08-30T12:01:00.000000Z",
      text: "same bytes\n",
      artifact_id: first.artifact_id
    )
    correction = observation_stream_event(
      Coordinator::Write::Events::DevelopmentArtifactClassificationCorrectedV1.new(
        observation_id: second_observation.observation_id,
        artifact_id: second.artifact_id,
        classification_revision: 2,
        title: "Corrected title",
        kind: "documentation",
        labels: %w[corrected docs],
        reason: "Correct imported classification",
        corrected_at: "2026-08-30T12:02:00.000000Z"
      ),
      observation_id: second_observation.observation_id,
      revision: 1,
      position: 400
    )

    projector.call(correction)
    expect(repository.fetch(second.artifact_id, observation_id: second_observation.observation_id)).to be_nil

    projector.call(capture_event(first, position: 100))
    projector.call(observation_event(second_observation, position: 300))
    projector.call(observation_event(first_observation, position: 200))
    projector.call(correction)

    first_view = repository.fetch(first.artifact_id, observation_id: first_observation.observation_id)
    corrected_view = repository.fetch(second.artifact_id, observation_id: second_observation.observation_id)
    expect(first.artifact_id).to eq(second.artifact_id)
    expect(first_observation.observation_id).not_to eq(second_observation.observation_id)
    expect(first_view.artifact).to have_attributes(
      observation_id: first_observation.observation_id,
      title: "Captured evidence",
      classification_revision: 1,
      source: have_attributes(revision: "commit-a")
    )
    expect(corrected_view.artifact).to have_attributes(
      observation_id: second_observation.observation_id,
      title: "Corrected title",
      labels: %w[corrected docs],
      classification_revision: 2,
      classification_reason: "Correct imported classification",
      source: have_attributes(revision: "commit-b"),
      observed: have_attributes(event: have_attributes(type: "DevelopmentArtifactObserved")),
      classified: have_attributes(event: have_attributes(type: "DevelopmentArtifactClassificationCorrected"))
    )
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

  def capture_event(artifact, position:)
    payload = Coordinator::Write::Events::DevelopmentArtifactCapturedV2.new(
      artifact:,
      captured_at: "2026-08-30T12:00:00.000000Z"
    )
    artifact_stream_event(payload, artifact_id: artifact.artifact_id, revision: 0, position:)
  end

  def observation_event(observation, position:)
    payload = Coordinator::Write::Events::DevelopmentArtifactObservedV1.new(
      observation:,
      recorded_at: observation.source.observed_at
    )
    observation_stream_event(
      payload,
      observation_id: observation.observation_id,
      revision: 0,
      position:
    )
  end

  def relation_payload(source:, target:)
    target_value = Coordinator::Write::DevelopmentArtifacts::RelationTargetV1.new(
      kind: "artifact",
      id: target,
      status: "verified",
      name: nil,
      scope: nil
    )
    attributes = Coordinator::Write::DevelopmentArtifacts::RelationAttributesV1.new(
      path: nil,
      fragment: nil,
      normalized_locator: nil
    )
    relation = Coordinator::Write::DevelopmentArtifacts::RelationBuilder.new.call(
      source_artifact_id: source,
      relation: "derived_from",
      target: target_value,
      attributes:
    )
    Coordinator::Write::Events::DevelopmentArtifactRelationDeclaredV1.new(
      artifact_relation: relation,
      declared_at: "2026-08-30T12:01:00.000000Z"
    )
  end

  def relation_event(payload, revision:, position:)
    source_id = payload.respond_to?(:artifact_relation) ?
      payload.artifact_relation.source_artifact_id : payload.source_artifact_id
    artifact_stream_event(payload, artifact_id: source_id, revision:, position:)
  end

  def artifact_stream_event(payload, artifact_id:, revision:, position:)
    projection_event(
      payload:,
      stream: Coordinator::Write::StreamFactory.new.development_artifact(artifact_id),
      revision:,
      position:,
      markers: [ "development-artifact:#{artifact_id}" ]
    )
  end

  def observation_stream_event(payload, observation_id:, revision:, position:)
    projection_event(
      payload:,
      stream: Coordinator::Write::StreamFactory.new.development_artifact_observation(observation_id),
      revision:,
      position:,
      markers: [ "development-artifact-observation:#{observation_id}" ]
    )
  end

  def projection_event(payload:, stream:, revision:, position:, markers:)
    ProjectionEventFactory.build(
      payload:,
      stream:,
      stream_revision: revision,
      global_position: position,
      command_id: "cmd-artifact-projector-#{position}",
      policy_version: "development-artifact-repository/v1",
      actor_id: "agent-projector",
      correlation_id:,
      markers:
    )
  end

  def processed_events
    Coordinator::Read::ProcessedProjectionEvent.where(
      projection_name: "development-artifacts",
      projection_version: 5
    )
  end

  def relation_query
    Coordinator::Read::Queries::DevelopmentArtifactRelationList.new
  end
end
