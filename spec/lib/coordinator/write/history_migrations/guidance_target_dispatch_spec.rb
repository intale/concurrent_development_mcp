# frozen_string_literal: true

RSpec.describe "history migration guidance target dispatch", :event_store do
  let(:source_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:target_store) do
    Coordinator::Write::EventStore.new(client: PgEventstore.client(:migration_target))
  end
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:legacy_repository_id) { SecureRandom.uuid_v7 }
  let(:legacy_conversation_id) { "legacy-guidance-conversation" }
  let(:payload) do
    Coordinator::Write::Events::UserUtteranceRecordedV1.new(
      message_id: "legacy-guidance-message",
      conversation_id: legacy_conversation_id,
      text: "Preserve this project instruction",
      source: "mcp_client",
      anchors: Coordinator::Write::GuidanceAnchorsV1.new(
        repository_ids: [ legacy_repository_id ],
        change_set_id: nil,
        work_item_id: nil,
        attempt_id: nil
      ),
      recorded_at: "2026-08-01T10:00:00.000000Z"
    )
  end

  it "Given a planned legacy message, when it is applied, then the target conversation contains cohesive guidance facts" do
    persist_reference
    source_event = persist_guidance
    planner = Coordinator::Container["history_migrations.event_planning_dispatcher"]
    dispatcher = Coordinator::Container["history_migrations.event_dispatcher"]

    expect(
      planner.call(
        migration_id:,
        source_config_name: "default",
        source_upper_position: source_event.global_position,
        source_event:
      )
    ).to be_success

    write = dispatcher.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: source_event.global_position,
      source_event:
    ).value!

    conversation_id = write.events.first.data.fetch("conversation_id")
    target_events = target_store.read(
      Coordinator::Write::StreamFactory.new.conversation(conversation_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[UserUtteranceRecorded GuidanceMessageAnchored],
        maximum_count: 2,
        direction: :asc
      )
    )
    expect(target_events.map(&:type)).to eq(%w[UserUtteranceRecorded GuidanceMessageAnchored])
    expect(target_events.first.data).to include(
      "conversation_id" => conversation_id,
      "message_id" => source_event.id,
      "source" => "user",
      "text" => payload.text
    )
    expect(target_events.first.data).not_to include("anchors", "recorded_at")
    target_repository_id = target_events.last.data.fetch("anchor_id")
    expect(target_repository_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(target_repository_id).not_to eq(legacy_repository_id)
    expect(target_events.last.markers).to include("repository:#{target_repository_id}")
    expect(target_events.first.metadata.fetch("migration_source")).to include(
      "event_id" => source_event.id,
      "stream_id" => legacy_conversation_id
    )
  end

  def persist_reference
    source_store.append(
      Coordinator::Write::StreamFactory.new.repository(legacy_repository_id),
      [
        PgEventstore::Event.new(
          id: SecureRandom.uuid_v7,
          type: "LegacyRepositoryRegistered",
          data: {},
          metadata: { "schema_version" => 1 },
          correlation_id: SecureRandom.uuid_v7
        )
      ]
    )
  end

  def persist_guidance
    source_store.append(
      Coordinator::Write::StreamFactory.new.conversation(legacy_conversation_id),
      [
        PgEventstore::Event.new(
          id: SecureRandom.uuid_v7,
          type: payload.class.event_type,
          data: payload.to_h,
          metadata: {
            "schema_version" => payload.class.schema_version,
            "command_id" => "legacy-guidance-command",
            "actor_kind" => "user",
            "actor_id" => "project-owner",
            "recorded_by" => "coordinator"
          },
          markers: [ "message:#{payload.message_id}", "conversation:#{payload.conversation_id}" ],
          correlation_id: SecureRandom.uuid_v7
        )
      ]
    ).sole
  end
end
