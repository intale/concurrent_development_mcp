# frozen_string_literal: true

RSpec.describe "post-remodel work-intention history migration", :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:registry) { Coordinator::Container["history_migrations.transformer_registry"] }
  let(:input_context_resolver) do
    Coordinator::Container["history_migrations.legacy_work_intention_input_context_resolver"]
  end
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:repository_id) { SecureRandom.uuid_v7 }
  let(:change_set_id) { "source-change-set" }
  let(:work_item_id) { "source-work-item" }
  let(:attempt_id) { "source-attempt" }
  let(:resource_id) { SecureRandom.uuid_v7 }
  let(:set_id) { SecureRandom.uuid_v7 }
  let(:intention_id) { SecureRandom.uuid_v7 }

  it "rebinds the set, member, resource, boundary markers, and lifecycle to target UUIDs" do
    seed_source_entities
    set_stream = stream("DevelopmentCoordination", "WorkIntentionSet", set_id)
    created = persist_payload(
      set_stream,
      Coordinator::Write::Events::WorkIntentionSetCreatedV1.new(
        set_id:,
        attempt_id:,
        work_item_id:,
        change_set_id:,
        repository_id:
      )
    )
    intention_stream = stream(
      "DevelopmentCoordination",
      "ResourceWorkIntention",
      intention_id
    )
    declared = persist_payload(
      intention_stream,
      Coordinator::Write::Events::ResourceWorkIntentionDeclaredV1.new(
        intention_id:,
        set_id:,
        resource_id:,
        repository_id:,
        change_set_id:,
        work_item_id:,
        attempt_id:,
        agent_id: "codex",
        mode: "shared",
        purpose: "Migrate the source range",
        context: "A25",
        object_format: "sha1",
        base_commit_oid: "a" * 40,
        base_blob_oid: "b" * 40,
        fencing_token: 7,
        expires_at: "2026-09-17T14:00:00.000000Z"
      )
    )
    member = persist_payload(
      set_stream,
      Coordinator::Write::Events::WorkIntentionAddedToSetV1.new(
        set_id:,
        intention_id:,
        resource_id:
      )
    )
    renewed = persist_payload(
      intention_stream,
      Coordinator::Write::Events::ResourceWorkIntentionRenewedV1.new(
        intention_id:,
        resource_id:,
        fencing_token: 7,
        expires_at: "2026-09-17T15:00:00.000000Z"
      )
    )
    upper_position = renewed.global_position

    created_fact = transform(created, upper_position:).value!.sole
    declared_fact = transform(declared, upper_position:).value!.sole
    member_fact = transform(member, upper_position:).value!.sole
    renewed_fact = transform(renewed, upper_position:).value!.sole
    target_set_id = created_fact.event.set_id
    target_intention_id = declared_fact.event.intention_id
    target_resource_id = declared_fact.event.resource_id

    expect(created_fact.event).to have_attributes(
      set_id: a_string_matching(Coordinator::Shared::Types::UUID_V7_PATTERN),
      repository_id: a_string_matching(Coordinator::Shared::Types::UUID_V7_PATTERN),
      change_set_id: a_string_matching(Coordinator::Shared::Types::UUID_V7_PATTERN),
      work_item_id: a_string_matching(Coordinator::Shared::Types::UUID_V7_PATTERN),
      attempt_id: a_string_matching(Coordinator::Shared::Types::UUID_V7_PATTERN)
    )
    expect(declared_fact.event).to have_attributes(
      intention_id: a_string_matching(Coordinator::Shared::Types::UUID_V7_PATTERN),
      set_id: target_set_id,
      resource_id: a_string_matching(Coordinator::Shared::Types::UUID_V7_PATTERN),
      repository_id: created_fact.event.repository_id,
      change_set_id: created_fact.event.change_set_id,
      work_item_id: created_fact.event.work_item_id,
      attempt_id: created_fact.event.attempt_id,
      mode: "shared",
      purpose: "Migrate the source range",
      context: "A25",
      expires_at: "2026-09-17T14:00:00.000000Z"
    )
    expect(member_fact.target_stream).to eq(created_fact.target_stream)
    expect(member_fact.event).to have_attributes(
      set_id: target_set_id,
      intention_id: target_intention_id,
      resource_id: target_resource_id
    )
    expect(renewed_fact.target_stream).to eq(declared_fact.target_stream)
    expect(renewed_fact.event).to have_attributes(
      intention_id: target_intention_id,
      resource_id: target_resource_id,
      fencing_token: 7,
      expires_at: "2026-09-17T15:00:00.000000Z"
    )
    expect(declared_fact.markers).to include(
      "scope:project:test",
      "repository:#{created_fact.event.repository_id}",
      "change-set:#{created_fact.event.change_set_id}",
      "work-item:#{created_fact.event.work_item_id}",
      "attempt:#{created_fact.event.attempt_id}",
      "work-intention-set:#{target_set_id}",
      "resource:#{target_resource_id}",
      "resource-kind:file",
      "work-intention:#{target_intention_id}"
    )
    expect(declared_fact.markers).to include(
      a_string_matching(/role=\d+:resource-exact(?:\||$)/),
      a_string_matching(/role=\d+:resource-within(?:\||$)/)
    )
    expect(declared_fact.event.to_h.values).not_to include(
      set_id,
      intention_id,
      resource_id,
      repository_id,
      change_set_id,
      work_item_id,
      attempt_id
    )

    input_context = input_context_resolver.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event: renewed,
      attempt_id:,
      lease_set_id: set_id
    )
    expect(input_context).to be_success
    expect(input_context.value!).to have_attributes(
      target_set_stream: created_fact.target_stream,
      set_id: target_set_id,
      repository_id: created_fact.event.repository_id,
      change_set_id: created_fact.event.change_set_id,
      work_item_id: created_fact.event.work_item_id,
      attempt_id: created_fact.event.attempt_id
    )
    expect(input_context.value!.members.sole).to have_attributes(
      target_stream: declared_fact.target_stream,
      source_lease_id: intention_id,
      intention_id: target_intention_id,
      resource_id: target_resource_id,
      resource_kind: "file",
      resource_path: "app/models/user.rb",
      base_blob_oid: "b" * 40,
      fencing_token: 7
    )
  end

  def seed_source_entities
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
    persist_raw(stream("DevelopmentPlanning", "ChangeSet", change_set_id), type: "ChangeSetCreated")
    persist_raw(stream("DevelopmentExecution", "WorkItem", work_item_id), type: "WorkItemCreated")
    persist_raw(stream("DevelopmentExecution", "Attempt", attempt_id), type: "AttemptAuthorized")
    persist_payload(
      stream("DevelopmentCoordination", "Resource", resource_id),
      Coordinator::Write::Events::ResourceIdentityV1::Registered.new(
        resource_id:,
        repository_id:,
        kind: "file",
        normalized_path: "app/models/user.rb",
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
end
