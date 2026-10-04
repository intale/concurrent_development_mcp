# frozen_string_literal: true

RSpec.describe "history migration command and Task target dispatch", :event_store do
  let(:source_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:target_store) do
    Coordinator::Write::EventStore.new(client: PgEventstore.client(:migration_target))
  end
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:old_command_id) { "legacy-dispatch-command" }
  let(:old_task_id) { SecureRandom.uuid_v7 }
  let(:correlation_id) { SecureRandom.uuid_v7 }
  let(:command_input) do
    Coordinator::Write::CommandInputDocuments::CreateChangeSetV1.new(
      schema: "command-input/v1",
      command_id: old_command_id,
      tool_name: "change_set_create",
      input: Coordinator::Write::CommandInputDocuments::CreateChangeSetInputV1.new(
        actor: Coordinator::Write::CommandInputDocuments::ActorV1.new(
          actor_kind: "agent",
          actor_id: "agent-luna-a"
        ),
        change_set_id: "legacy-change-set",
        goal: "Migrate command facts",
        acceptance_criteria: [ "Target history is cohesive" ]
      )
    )
  end
  let(:submitted_payload) do
    Coordinator::Write::HistoryMigrations::LegacyEvents::CoordinationTaskSubmittedV2.new(
      task_id: old_task_id,
      tool_name: "change_set_create",
      command_id: old_command_id,
      command_input:,
      submitted_at: "2026-08-01T10:00:00.000000Z",
      ttl_ms: nil,
      poll_interval_ms: 500
    )
  end
  let(:completion_payload) do
    Coordinator::Write::HistoryMigrations::LegacyEvents::CommandCompletedV1.new(
      command_id: old_command_id,
      tool_name: "change_set_create",
      canonical_input_digest: "sha256:#{'a' * 64}",
      status: "ok",
      summary: "ChangeSet created.",
      receipt: old_command_id,
      data: Coordinator::Write::CommandReceiptData::ChangeSet.new(
        change_set_id: "legacy-change-set"
      ),
      warnings: [],
      next_actions: [],
      emitted_events: [],
      completed_at: "2026-08-01T10:01:00.000000Z"
    )
  end

  it "Given a completely planned source pair, when it is applied, then target streams contain cohesive facts and typed provenance" do
    change_set_event = persist_change_set.sole
    submitted_event = persist(submitted_payload, stream_name: "CoordinationTask", stream_id: old_task_id)
    completion_event = persist(completion_payload, stream_name: "Command", stream_id: old_command_id)
    upper_position = completion_event.global_position
    planner = Coordinator::Container["history_migrations.event_planning_dispatcher"]
    dispatcher = Coordinator::Container["history_migrations.event_dispatcher"]

    [ change_set_event, submitted_event, completion_event ].each do |event|
      result = planner.call(
        migration_id:,
        source_config_name: "default",
        source_upper_position: upper_position,
        source_event: event
      )
      expect(result).to be_success, result.failure.to_h.inspect
    end

    creation_write = HistoryMigrationWaveDispatch.call(
      dispatcher:, migration_id:, source_config_name: "default",
      source_upper_position: upper_position, source_event: change_set_event
    ).value!

    submitted_write = HistoryMigrationWaveDispatch.call(
      dispatcher:,
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event: submitted_event
    ).value!
    completion_write = HistoryMigrationWaveDispatch.call(
      dispatcher:,
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event: completion_event
    ).value!

    command_id = submitted_write.events.find { _1.type == "CommandRegistered" }.data.fetch("command_id")
    task_id = submitted_write.events.find { _1.type == "CoordinationTaskSubmitted" }.data.fetch("task_id")
    command_events = target_store.read(
      Coordinator::Write::StreamFactory.new.command(command_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[CommandRegistered CommandSucceeded],
        maximum_count: 2,
        direction: :asc
      )
    )
    task_events = target_store.read(
      Coordinator::Write::StreamFactory.new.coordination_task(task_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "CoordinationTaskSubmitted" ],
        maximum_count: 1,
        direction: :asc
      )
    )

    expect(command_events.map(&:type)).to eq(%w[CommandRegistered CommandSucceeded])
    expect(command_events.first.metadata).to include("actor_kind" => "agent", "actor_id" => "agent-luna-a")
    expect(command_events.map { _1.metadata.fetch("command_id") }.uniq).to eq([ command_id ])
    expect(creation_write.events.map { _1.metadata.fetch("command_id") }.uniq).to eq([ command_id ])
    attributed = target_store.read_command_events(
      Coordinator::Write::CommandEventReadCriteria.new(
        command_id:, through_global_position: command_events.last.global_position, maximum_count: 10
      )
    )
    expect(attributed.map(&:id)).to match_array(creation_write.events.map(&:id))
    expect(task_events.map(&:type)).to eq([ "CoordinationTaskSubmitted" ])
    expect(completion_write.events.sole.id).to eq(command_events.last.id)
    expect(command_events.first.metadata.fetch("canonical_input_digest")).to match(
      Coordinator::Shared::Types::SHA256_DIGEST_PATTERN
    )
    expect(command_events.first.metadata.fetch("migration_source")).to include(
      "event_id" => submitted_event.id,
      "created_at" => submitted_event.created_at.utc.iso8601(6)
    )
    expect(command_events.flat_map { _1.data.keys }).not_to include("completed_at", "submitted_at")
  end

  def persist_change_set
    payload = Coordinator::Write::Events::ChangeSetCreatedV1.new(
      change_set_id: "legacy-change-set",
      goal: "Migrate command facts",
      created_at: "2026-08-01T09:59:00.000000Z"
    )
    source_store.append(
      Coordinator::Write::StreamReference.new(
        context: "DevelopmentPlanning",
        stream_name: "ChangeSet",
        stream_id: payload.change_set_id
      ),
      [
        PgEventstore::Event.new(
          id: SecureRandom.uuid_v7,
          type: payload.class.event_type,
          data: payload.to_h,
          metadata: {
            "schema_version" => payload.class.schema_version,
            "command_id" => old_command_id,
            "actor_kind" => "agent",
            "actor_id" => "agent-luna-a",
            "recorded_by" => "coordinator"
          },
          markers: [ "change-set:#{payload.change_set_id}" ],
          correlation_id:
        )
      ]
    )
  end

  def persist(payload, stream_name:, stream_id:)
    source_store.append(
      Coordinator::Write::StreamReference.new(
        context: "CoordinatorControl",
        stream_name:,
        stream_id:
      ),
      [
        PgEventstore::Event.new(
          id: SecureRandom.uuid_v7,
          type: payload.class.event_type,
          data: payload.to_h,
          metadata: {
            "schema_version" => payload.class.schema_version,
            "command_id" => old_command_id,
            "actor_kind" => "agent",
            "actor_id" => "agent-luna-a",
            "recorded_by" => "coordinator"
          },
          markers: [ "command:#{old_command_id}", "task:#{old_task_id}" ],
          correlation_id:
        )
      ]
    ).sole
  end
end
