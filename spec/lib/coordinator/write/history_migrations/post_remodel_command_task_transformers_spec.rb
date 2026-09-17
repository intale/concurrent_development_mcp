# frozen_string_literal: true

RSpec.describe "post-remodel Command, Task, and ProcessStep history migration", :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:registry) { Coordinator::Container["history_migrations.transformer_registry"] }
  let(:planning_dispatcher) { Coordinator::Container["history_migrations.event_planning_dispatcher"] }
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:repository_id) { SecureRandom.uuid_v7 }
  let(:change_set_id) { "source-change-set" }
  let(:work_item_id) { "source-work-item" }
  let(:attempt_id) { "source-attempt" }
  let(:resource_id) { SecureRandom.uuid_v7 }

  it "rebinds a legacy lease Task to a current work-intention command document" do
    seed_command_entities
    command_id = SecureRandom.uuid_v7
    task_id = SecureRandom.uuid_v7
    command = persist_payload(
      stream("CoordinatorControl", "Command", command_id),
      Coordinator::Write::Events::CommandRegisteredV1.new(
        command_id:,
        request_id: "request-legacy-reservation",
        tool_name: "write_set_reserve"
      )
    )
    task = persist_raw(
      stream("CoordinatorControl", "CoordinationTask", task_id),
      type: "CoordinationTaskSubmitted",
      schema_version: 3,
      data: {
        task_id:,
        command_id:,
        tool_name: "write_set_reserve",
        command_input: {
          schema: "command-input/v1",
          command_id:,
          tool_name: "write_set_reserve",
          input: {
            actor: { actor_kind: "agent", actor_id: "codex" },
            change_set_id:,
            work_item_id:,
            attempt_id:,
            repository_id:,
            base_commit_oid: "a" * 40,
            resources: [ { resource_id:, base_blob_oid: nil } ],
            lease_duration_seconds: 3_600
          }
        },
        poll_interval_ms: 500,
        ttl_ms: nil
      }
    )
    started = persist_payload(
      stream("CoordinatorControl", "CoordinationTask", task_id),
      Coordinator::Write::Events::CoordinationTaskExecutionStartedV2.new(task_id:)
    )
    upper_position = started.global_position

    command_fact = transform(command, upper_position:).value!.sole
    task_fact = transform(task, upper_position:).value!.sole
    started_fact = transform(started, upper_position:).value!.sole
    migrated = task_fact.event.command_input
    migrated_resource = migrated.input.resources.sole

    expect(task_fact.event).to be_a(Coordinator::Write::Events::CoordinationTaskSubmittedV3)
    expect(task_fact.event.tool_name).to eq("work_intention_set_declare")
    expect(migrated).to be_a(Coordinator::Write::CommandInputDocuments::ReserveWriteSetV1)
    expect(migrated).to have_attributes(
      command_id: command_fact.event.command_id,
      tool_name: "work_intention_set_declare"
    )
    expect(migrated.input).to have_attributes(
      ttl_seconds: 3_600,
      repository_id: a_string_matching(Coordinator::Shared::Types::UUID_V7_PATTERN),
      change_set_id: a_string_matching(Coordinator::Shared::Types::UUID_V7_PATTERN),
      work_item_id: a_string_matching(Coordinator::Shared::Types::UUID_V7_PATTERN),
      attempt_id: a_string_matching(Coordinator::Shared::Types::UUID_V7_PATTERN)
    )
    expect(migrated_resource).to have_attributes(
      resource_id: a_string_matching(Coordinator::Shared::Types::UUID_V7_PATTERN),
      mode: "exclusive",
      purpose: "Preserve legacy exclusive lease semantics",
      context: nil
    )
    expect(migrated.to_h.values).not_to include(command_id)
    expect(migrated.input.to_h.values).not_to include(
      repository_id,
      change_set_id,
      work_item_id,
      attempt_id,
      resource_id
    )
    expect(started_fact.target_stream).to eq(task_fact.target_stream)
    expect(started_fact.event.task_id).to eq(task_fact.event.task_id)
    expect(task_fact.metadata_extension.canonical_input_digest).to match(/\Asha256:[0-9a-f]{64}\z/)
  end

  it "rebinds ProcessStep parents and subjects through the persisted migration plan" do
    persist_raw(stream("DevelopmentPlanning", "ChangeSet", change_set_id), type: "ChangeSetCreated")
    persist_raw(stream("DevelopmentExecution", "WorkItem", work_item_id), type: "WorkItemCreated")
    completed = persist_payload(
      stream("DevelopmentExecution", "WorkItem", work_item_id),
      Coordinator::Write::Events::WorkItemCompletedV2.new(work_item_id:)
    )
    planned = planning_dispatcher.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: completed.global_position,
      source_event: completed
    )
    expect(planned).to be_success

    source_command_id = SecureRandom.uuid_v7
    process_step_id = SecureRandom.uuid_v7
    process_step = persist_payload(
      stream("CoordinatorControl", "ProcessStep", process_step_id),
      Coordinator::Write::Events::ProcessStepPlannedV1.new(
        process_step_id:,
        process_name: "build-progress",
        step_name: "complete-change-set",
        source_event_id: completed.id,
        subject_kind: "change-set",
        subject_id: change_set_id,
        target_command_id: source_command_id,
        target_entity_id: nil
      )
    )

    fact = transform(process_step, upper_position: process_step.global_position).value!.sole

    expect(fact.event).to have_attributes(
      source_event_id: planned.value!.sole.target_event.event_id,
      subject_kind: "change-set",
      subject_id: a_string_matching(Coordinator::Shared::Types::UUID_V7_PATTERN),
      target_command_id: a_string_matching(Coordinator::Shared::Types::UUID_V7_PATTERN),
      target_entity_id: nil
    )
    expect(fact.event.source_event_id).not_to eq(completed.id)
    expect(fact.event.subject_id).not_to eq(change_set_id)
    expect(fact.event.target_command_id).not_to eq(source_command_id)
    expect(fact.markers.sole).to start_with("compound:process-step:v2|")
  end

  it "keeps guidance command input identities aligned with migrated guidance facts" do
    command_id = SecureRandom.uuid_v7
    task_id = SecureRandom.uuid_v7
    conversation_id = "source-conversation"
    message_id = "source-message"
    persist_payload(
      stream("CoordinatorControl", "Command", command_id),
      Coordinator::Write::Events::CommandRegisteredV1.new(
        command_id:,
        request_id: "request-guidance",
        tool_name: "guidance_record"
      )
    )
    command_input = Coordinator::Write::CommandInputDocuments::RecordGuidanceV1.new(
      schema: "command-input/v1",
      command_id:,
      tool_name: "guidance_record",
      input: Coordinator::Write::CommandInputDocuments::RecordGuidanceInputV1.new(
        actor: Coordinator::Write::CommandInputDocuments::ActorV1.new(
          actor_kind: "agent",
          actor_id: "codex"
        ),
        message_id:,
        conversation_id:,
        source: "agent_forwarded",
        text: "Preserve this instruction",
        anchors: Coordinator::Write::CommandInputDocuments::GuidanceAnchorsV1.new(
          repository_ids: [],
          change_set_id: nil,
          work_item_id: nil,
          attempt_id: nil
        )
      )
    )
    task = persist_payload(
      stream("CoordinatorControl", "CoordinationTask", task_id),
      Coordinator::Write::Events::CoordinationTaskSubmittedV3.new(
        task_id:,
        command_id:,
        tool_name: "guidance_record",
        command_input:,
        poll_interval_ms: 500,
        ttl_ms: nil
      )
    )
    guidance = persist_payload(
      stream("HumanGuidance", "Conversation", conversation_id),
      Coordinator::Write::Events::UserUtteranceForwardedByAgentV2.new(
        conversation_id:,
        message_id:,
        source: "agent_forwarded",
        text: "Preserve this instruction"
      ),
      markers: [ "message:#{message_id}" ]
    )
    upper_position = guidance.global_position

    task_fact = transform(task, upper_position:).value!.sole
    guidance_fact = transform(guidance, upper_position:).value!.sole
    migrated_input = task_fact.event.command_input.input

    expect(migrated_input).to have_attributes(
      conversation_id: guidance_fact.event.conversation_id,
      message_id: guidance_fact.event.message_id
    )
    expect(migrated_input.conversation_id).not_to eq(conversation_id)
    expect(migrated_input.message_id).not_to eq(message_id)
  end

  def seed_command_entities
    persist_repository
    persist_raw(stream("DevelopmentPlanning", "ChangeSet", change_set_id), type: "ChangeSetCreated")
    persist_raw(stream("DevelopmentExecution", "WorkItem", work_item_id), type: "WorkItemCreated")
    persist_raw(stream("DevelopmentExecution", "Attempt", attempt_id), type: "AttemptAuthorized")
    persist_payload(
      stream("DevelopmentCoordination", "Resource", resource_id),
      Coordinator::Write::Events::ResourceIdentityV1::Registered.new(
        resource_id:,
        repository_id:,
        kind: "file",
        normalized_path: "README.md",
        registered_at: "2026-09-01T00:00:00.000000Z"
      )
    )
  end

  def persist_repository
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
end
