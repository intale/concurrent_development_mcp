# frozen_string_literal: true

RSpec.describe "post-remodel Development Memory history migration", :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:registry) { Coordinator::Container["history_migrations.transformer_registry"] }
  let(:planning_dispatcher) { Coordinator::Container["history_migrations.event_planning_dispatcher"] }
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:artifact_id) { SecureRandom.uuid_v7 }

  it "rebinds artifact facts and observation references while preserving content descriptors" do
    artifact_stream = stream("DevelopmentMemory", "DevelopmentArtifact", artifact_id)
    created = persist_payload(
      artifact_stream,
      Coordinator::Write::Events::DevelopmentArtifactCreatedV1.new(artifact_id:)
    )
    scope = persist_payload(
      artifact_stream,
      Coordinator::Write::Events::DevelopmentArtifactScopeChangedV1.new(
        artifact_id:,
        scope: "project:test"
      )
    )
    source = persist_payload(
      artifact_stream,
      Coordinator::Write::Events::DevelopmentArtifactSourceChangedV1.new(
        artifact_id:,
        source_kind: "local_file",
        locator: "docs/README.md",
        revision: "a" * 40,
        observed_at: "2026-09-01T00:00:00.000000Z"
      ),
      metadata: { "collector" => "codex" }
    )
    content = persist_payload(
      artifact_stream,
      Coordinator::Write::Events::DevelopmentArtifactContentChangedV1.new(
        artifact_id:,
        content: "hello"
      ),
      metadata: {
        "encoding" => "utf-8",
        "media_type" => "text/markdown",
        "byte_size" => 5,
        "content_sha256" => "sha256:#{'a' * 64}"
      }
    )
    planned_content = planning_dispatcher.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: content.global_position,
      source_event: content
    )
    expect(planned_content).to be_success

    observation_id = SecureRandom.uuid_v7
    observation_stream = stream(
      "DevelopmentMemory",
      "DevelopmentArtifactObservation",
      observation_id
    )
    recorded = persist_payload(
      observation_stream,
      Coordinator::Write::Events::DevelopmentArtifactObservationRecordedV1.new(observation_id:)
    )
    linked = persist_payload(
      observation_stream,
      Coordinator::Write::Events::DevelopmentArtifactObservationFactLinkedV1.new(
        observation_id:,
        artifact_id:,
        role: "content",
        observed_fact: event_reference(content)
      )
    )
    upper_position = linked.global_position

    created_fact = transform(created, upper_position:).value!.sole
    scope_fact = transform(scope, upper_position:).value!.sole
    source_fact = transform(source, upper_position:).value!.sole
    content_fact = transform(content, upper_position:).value!.sole
    recorded_fact = transform(recorded, upper_position:).value!.sole
    linked_fact = transform(linked, upper_position:).value!.sole
    target_artifact_id = created_fact.event.artifact_id

    expect([ scope_fact, source_fact, content_fact ].map(&:target_stream).uniq).to contain_exactly(
      created_fact.target_stream
    )
    expect([ scope_fact.event.artifact_id, source_fact.event.artifact_id, content_fact.event.artifact_id ]).to all(
      eq(target_artifact_id)
    )
    expect(target_artifact_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(target_artifact_id).not_to eq(artifact_id)
    expect(created_fact.markers).to include(
      "development-artifact:#{target_artifact_id}",
      a_string_starting_with("compound:development-artifact-natural-key:v2|")
    )
    expect(content_fact.metadata_extension).to have_attributes(
      encoding: "utf-8",
      media_type: "text/markdown",
      byte_size: 5,
      content_sha256: "sha256:#{'a' * 64}"
    )
    expect(source_fact.metadata_extension.collector).to eq("codex")
    expect(linked_fact.target_stream).to eq(recorded_fact.target_stream)
    expect(linked_fact.event).to have_attributes(
      observation_id: recorded_fact.event.observation_id,
      artifact_id: target_artifact_id,
      observed_fact: planned_content.value!.sole.target_event
    )
    expect(linked_fact.event.observed_fact.event_id).not_to eq(content.id)
  end

  it "rebinds relation targets and keeps the relation natural key on target identities" do
    persist_payload(
      stream("DevelopmentMemory", "DevelopmentArtifact", artifact_id),
      Coordinator::Write::Events::DevelopmentArtifactCreatedV1.new(artifact_id:)
    )
    attempt_id = "source-attempt"
    persist_raw(stream("DevelopmentExecution", "Attempt", attempt_id), type: "AttemptAuthorized")
    relation_id = SecureRandom.uuid_v7
    relation = persist_payload(
      stream("DevelopmentMemory", "DevelopmentArtifactRelation", relation_id),
      Coordinator::Write::Events::DevelopmentArtifactRelationDeclaredV2.new(
        relation_id:,
        source_artifact_id: artifact_id,
        relation: "evidences",
        target_kind: "attempt",
        target_id: attempt_id,
        path: nil,
        fragment: nil,
        normalized_locator: nil
      )
    )

    relation_fact = transform(relation, upper_position: relation.global_position).value!.sole

    expect(relation_fact.event).to have_attributes(
      relation_id: a_string_matching(Coordinator::Shared::Types::UUID_V7_PATTERN),
      source_artifact_id: a_string_matching(Coordinator::Shared::Types::UUID_V7_PATTERN),
      target_kind: "attempt",
      target_id: a_string_matching(Coordinator::Shared::Types::UUID_V7_PATTERN)
    )
    expect(relation_fact.event.relation_id).not_to eq(relation_id)
    expect(relation_fact.event.source_artifact_id).not_to eq(artifact_id)
    expect(relation_fact.event.target_id).not_to eq(attempt_id)
    expect(relation_fact.markers).to include(
      "development-artifact:#{relation_fact.event.source_artifact_id}",
      "development-artifact-relation:#{relation_fact.event.relation_id}",
      a_string_starting_with("compound:development-artifact-relation-natural-key:v2|")
    )
  end

  it "keeps one migrated conversation while assigning distinct identities to multiple messages" do
    repository_id = SecureRandom.uuid_v7
    persist_repository(repository_id)
    conversation_id = "source-conversation"
    conversation_stream = stream("HumanGuidance", "Conversation", conversation_id)
    first = persist_payload(
      conversation_stream,
      Coordinator::Write::Events::UserUtteranceForwardedByAgentV2.new(
        conversation_id:,
        message_id: "source-message-1",
        source: "agent_forwarded",
        text: "First instruction"
      ),
      markers: [ "message:source-message-1" ]
    )
    second = persist_payload(
      conversation_stream,
      Coordinator::Write::Events::UserUtteranceForwardedByAgentV2.new(
        conversation_id:,
        message_id: "source-message-2",
        source: "agent_forwarded",
        text: "Second instruction"
      ),
      markers: [ "message:source-message-2" ]
    )
    anchor = persist_payload(
      conversation_stream,
      Coordinator::Write::Events::GuidanceMessageAnchoredV1.new(
        conversation_id:,
        message_id: "source-message-2",
        anchor_kind: "repository",
        anchor_id: repository_id
      )
    )
    upper_position = anchor.global_position

    first_fact = transform(first, upper_position:).value!.sole
    second_fact = transform(second, upper_position:).value!.sole
    anchor_fact = transform(anchor, upper_position:).value!.sole

    expect(first_fact.target_stream).to eq(second_fact.target_stream)
    expect(first_fact.event.conversation_id).to eq(second_fact.event.conversation_id)
    expect(first_fact.event.message_id).not_to eq(second_fact.event.message_id)
    expect(anchor_fact.target_stream).to eq(second_fact.target_stream)
    expect(anchor_fact.event).to have_attributes(
      conversation_id: second_fact.event.conversation_id,
      message_id: second_fact.event.message_id,
      anchor_kind: "repository",
      anchor_id: a_string_matching(Coordinator::Shared::Types::UUID_V7_PATTERN)
    )
    expect(anchor_fact.event.anchor_id).not_to eq(repository_id)
  end

  def persist_repository(repository_id)
    persist_payload(
      stream("DevelopmentPlanning", "Repository", repository_id),
      Coordinator::Write::Events::RepositoryRegisteredV1.new(
        repository_id:,
        scope: "project:test",
        repository_key: "test-repository",
        display_name: nil,
        paths: [],
        remotes: [],
        registered_at: "2026-09-01T00:00:00.000000Z"
      )
    )
  end

  def transform(source_event, upper_position:)
    registry.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event:
    )
  end

  def persist_payload(target_stream, payload, metadata: {}, markers: [])
    persist_raw(
      target_stream,
      type: payload.class.event_type,
      data: payload.to_h,
      schema_version: payload.class.schema_version,
      metadata:,
      markers:
    )
  end

  def persist_raw(target_stream, type:, data: {}, schema_version: 1, metadata: {}, markers: [])
    event_store.append(
      target_stream,
      [
        PgEventstore::Event.new(
          id: SecureRandom.uuid_v7,
          type:,
          data:,
          metadata: {
            "schema_version" => schema_version,
            "command_id" => SecureRandom.uuid_v7,
            "actor_kind" => "agent",
            "actor_id" => "codex",
            "recorded_by" => "coordinator"
          }.merge(metadata),
          markers:,
          correlation_id: SecureRandom.uuid_v7
        )
      ]
    ).sole
  end

  def stream(context, stream_name, stream_id)
    Coordinator::Write::StreamReference.new(context:, stream_name:, stream_id:)
  end

  def event_reference(event)
    Coordinator::Write::EventReference.new(
      event_id: event.id,
      type: event.type,
      stream_context: event.stream.context,
      stream_name: event.stream.stream_name,
      stream_id: event.stream.stream_id,
      stream_revision: event.stream_revision
    )
  end
end
