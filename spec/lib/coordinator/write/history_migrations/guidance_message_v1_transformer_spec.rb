# frozen_string_literal: true

RSpec.describe Coordinator::Write::HistoryMigrations::GuidanceMessageV1Transformer, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:allocator) do
    Coordinator::Write::HistoryMigrations::StreamIdentityAllocator.new(event_store:)
  end
  let(:resolver) do
    Coordinator::Write::HistoryMigrations::LegacyEntityReferenceResolver.new(
      event_store:,
      stream_identity_allocator: allocator
    )
  end
  let(:transformer) do
    described_class.new(stream_identity_allocator: allocator, entity_reference_resolver: resolver)
  end
  let(:legacy_ids) do
    {
      repository: SecureRandom.uuid_v7,
      change_set: "legacy-change-set",
      work_item: "legacy-work-item",
      attempt: "legacy-attempt",
      conversation: "legacy-conversation",
      message: "legacy-message"
    }
  end
  let(:anchors) do
    Coordinator::Write::GuidanceAnchorsV1.new(
      repository_ids: [ legacy_ids.fetch(:repository) ],
      change_set_id: legacy_ids.fetch(:change_set),
      work_item_id: legacy_ids.fetch(:work_item),
      attempt_id: legacy_ids.fetch(:attempt)
    )
  end

  before do
    persist_reference("DevelopmentPlanning", "Repository", legacy_ids.fetch(:repository))
    persist_reference("DevelopmentPlanning", "ChangeSet", legacy_ids.fetch(:change_set))
    persist_reference("DevelopmentExecution", "WorkItem", legacy_ids.fetch(:work_item))
    persist_reference("DevelopmentExecution", "Attempt", legacy_ids.fetch(:attempt))
  end

  it "Given a legacy user message, when it is transformed, then its occurrence copy is removed and every anchor uses a migrated identity" do
    payload = Coordinator::Write::Events::UserUtteranceRecordedV1.new(
      message_id: legacy_ids.fetch(:message),
      conversation_id: legacy_ids.fetch(:conversation),
      text: "Use the target guidance contract",
      source: "mcp_client",
      anchors:,
      recorded_at: "2026-08-01T10:00:00.000000Z"
    )
    source_event = persist_guidance(payload)

    facts = transform(source_event, payload).value!

    utterance, *anchor_facts = facts
    expect(utterance.event).to eq(
      Coordinator::Write::Events::UserUtteranceRecordedV2.new(
        conversation_id: utterance.target_stream.stream_id,
        message_id: source_event.id,
        source: "user",
        text: payload.text
      )
    )
    expect(utterance.target_stream).to have_attributes(
      context: "HumanGuidance",
      stream_name: "Conversation"
    )
    expect(utterance.target_stream.stream_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(utterance.target_stream.stream_id).not_to eq(payload.conversation_id)
    expect(anchor_facts.map { _1.event.anchor_kind }).to eq(%w[repository change_set work_item attempt])
    expect(anchor_facts.map { _1.event.anchor_id }).to all(match(Coordinator::Shared::Types::UUID_V7_PATTERN))
    expect(anchor_facts.map { _1.event.anchor_id }).not_to include(*legacy_ids.values)
    expect(facts.map(&:target_stream).uniq).to eq([ utterance.target_stream ])
    expect(facts.flat_map { _1.event.to_h.keys }).not_to include(:anchors, :recorded_at)
  end

  it "Given the same source message is retried, when identities are resolved, then the transformation is stable" do
    payload = Coordinator::Write::Events::UserUtteranceForwardedByAgentV1.new(
      message_id: legacy_ids.fetch(:message),
      conversation_id: legacy_ids.fetch(:conversation),
      text: "Forward the project-owner guidance",
      source: "agent_forwarded",
      anchors:,
      recorded_at: "2026-08-01T10:00:00.000000Z"
    )
    source_event = persist_guidance(payload)

    first = transform(source_event, payload).value!
    second = transform(source_event, payload).value!

    expect(second).to eq(first)
    expect(first.first.event).to be_a(Coordinator::Write::Events::UserUtteranceForwardedByAgentV2)
  end

  it "Given an anchor outside the frozen source range, when it is transformed, then migration fails closed" do
    payload = Coordinator::Write::Events::UserUtteranceRecordedV1.new(
      message_id: legacy_ids.fetch(:message),
      conversation_id: legacy_ids.fetch(:conversation),
      text: "Do not retain an unresolved anchor",
      source: "mcp_client",
      anchors: Coordinator::Write::GuidanceAnchorsV1.new(
        repository_ids: [ SecureRandom.uuid_v7 ],
        change_set_id: nil,
        work_item_id: nil,
        attempt_id: nil
      ),
      recorded_at: "2026-08-01T10:00:00.000000Z"
    )
    source_event = persist_guidance(payload)

    result = transform(source_event, payload)

    expect(result).to be_failure
    expect(result.failure).to have_attributes(
      code: :ambiguous_source_reference,
      event_type: "UserUtteranceRecorded",
      source_event_id: source_event.id
    )
  end

  def transform(source_event, payload)
    transformer.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: source_event.global_position,
      source_event:,
      source_payload: payload
    )
  end

  def persist_reference(context, stream_name, stream_id)
    persist(
      PgEventstore::Event.new(
        id: SecureRandom.uuid_v7,
        type: "LegacyEntityCreated",
        data: {},
        metadata: { "schema_version" => 1 },
        correlation_id: SecureRandom.uuid_v7
      ),
      context:,
      stream_name:,
      stream_id:
    )
  end

  def persist_guidance(payload)
    persist(
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
      ),
      context: "HumanGuidance",
      stream_name: "Conversation",
      stream_id: payload.conversation_id
    )
  end

  def persist(event, context:, stream_name:, stream_id:)
    event_store.append(
      Coordinator::Write::StreamReference.new(context:, stream_name:, stream_id:),
      [ event ]
    ).sole
  end
end
