# frozen_string_literal: true

RSpec.describe Coordinator::Processes::ProcessManagers::HistoryMigration, :event_store do
  let(:source_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:target_client) { PgEventstore.client(:migration_target) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:manager) { Coordinator::Container["process_managers.history_migration"] }
  let(:migration_id) { SecureRandom.uuid_v7 }

  it "plans the complete range before applying and idempotently redelivers a bounded cross-store page" do
    legacy = append_legacy_repository
    started = start_migration(through: legacy.global_position)

    manager.call(started)
    source_count = page_event("HistoryMigrationPageSourceEventCountRecorded")
    manager.call(source_count)

    page_id = source_count.stream.stream_id
    planned = page_stream(page_id).last
    expect(planned.type).to eq("HistoryMigrationPagePlanned")
    expect(target_repositories).to be_empty
    manager.call(planned)

    plan_completed = migration_event("HistoryMigrationPlanCompleted")
    application_events = []
    source = plan_completed
    4.times do |dependency_wave|
      manager.call(source)
      applied = page_stream(page_id).select do |event|
        event.type == "HistoryMigrationPageDependencyWaveApplied"
      end.fetch(dependency_wave)
      expect(applied.data["dependency_wave"] || applied.data[:dependency_wave]).to eq(dependency_wave)
      manager.call(applied)

      source = latest_migration_event("HistoryMigrationApplicationCursorAdvanced")
      application_events << source
    end
    manager.call(source)

    migration = Coordinator::Container["history_migrations.migration_loader"].call(migration_id)
    expect(migration).to be_completed
    expect(page_stream(source_count.stream.stream_id).map(&:type)).to eq(
      Coordinator::Write::HistoryMigrations::PageLoader::EVENT_TYPES.first(6) +
        ([ "HistoryMigrationPageDependencyWaveApplied" ] * 4) +
        [ "HistoryMigrationPageApplied" ]
    )
    target_events = target_repositories
    expect(target_events.length).to eq(1)
    expect(target_events.sole.stream.stream_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)

    wave_events = page_stream(page_id).select do |event|
      event.type == "HistoryMigrationPageDependencyWaveApplied"
    end
    [ started, source_count, planned, plan_completed, *wave_events, *application_events ].each do |event|
      manager.call(event)
    end
    expect(page_stream(source_count.stream.stream_id).length).to eq(11)
    expect(
      Coordinator::Container["history_migrations.migration_loader"].call(migration_id)
    ).to be_completed
  end

  it "does not plan or apply more work after the migration is abandoned" do
    legacy = append_legacy_repository
    started = start_migration(through: legacy.global_position)
    abandonment = Coordinator::Container["operations.execute_abandon_history_migration"].call_command(
      Coordinator::Write::Commands::AbandonHistoryMigration.new(
        command_id: "abandon-duplicate-history-migration",
        actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "migration-operator"),
        migration_id:,
        reason: "Accidental duplicate migration"
      )
    )
    expect(abandonment).to be_success

    manager.call(started)

    expect(history_migration_pages).to be_empty
    expect(target_repositories).to be_empty
    expect(
      Coordinator::Container["history_migrations.migration_loader"].call(migration_id)
    ).to be_abandoned
  end

  private

  def target_repositories
    target_client.read(
      PgEventstore::Stream.all_stream,
      options: {
        direction: :asc,
        max_count: 2,
        filter: {
          streams: [ { context: "DevelopmentPlanning", stream_name: "Repository" } ],
          event_types: [ "RepositoryRegistered" ]
        }
      }
    )
  end

  def append_legacy_repository
    payload = Coordinator::Write::Events::RepositoryRegisteredV1.new(
      repository_id: SecureRandom.uuid_v7,
      scope: "project:legacy",
      repository_key: "legacy-app",
      display_name: nil,
      paths: [],
      remotes: [],
      registered_at: "2026-01-01T12:00:00.000000Z"
    )
    source_store.append(
      Coordinator::Write::StreamReference.new(
        context: "LegacyDevelopmentPlanning",
        stream_name: "Repository",
        stream_id: "repository:v1:#{'a' * 64}"
      ),
      [
        PgEventstore::Event.new(
          id: SecureRandom.uuid_v7,
          type: "RepositoryRegistered",
          data: payload.to_h,
          metadata: { "schema_version" => 1 },
          correlation_id: SecureRandom.uuid_v7
        )
      ]
    ).sole
  end

  def start_migration(through:)
    operation = Coordinator::Write::Operations::ExecuteStartHistoryMigration.new(event_store: source_store)
    result = operation.call_command(
      Coordinator::Write::Commands::StartHistoryMigration.new(
        command_id: "history-migration-test",
        actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "test-agent"),
        migration_id:,
        source_config_name: "default",
        target_config_name: "migration_target",
        source_upper_position: through,
        page_size: 1
      )
    )
    expect(result).to be_success
    source_store.read(
      streams.history_migration(migration_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "HistoryMigrationStarted" ],
        maximum_count: 1,
        direction: :asc
      )
    ).sole
  end

  def page_event(type)
    source_store.read_global_marked(
      Coordinator::Write::GlobalMarkedEventReadCriteria.new(
        stream_context: "CoordinatorMaintenance",
        stream_name: "HistoryMigrationPage",
        event_types: [ type ],
        markers: [ "history-migration:#{migration_id}" ],
        maximum_count: 1,
        direction: :asc
      )
    ).sole
  end

  def history_migration_pages
    source_store.read_global_marked(
      Coordinator::Write::GlobalMarkedEventReadCriteria.new(
        stream_context: "CoordinatorMaintenance",
        stream_name: "HistoryMigrationPage",
        event_types: [ "HistoryMigrationPageCreated" ],
        markers: [ "history-migration:#{migration_id}" ],
        maximum_count: 1,
        direction: :asc
      )
    )
  end

  def migration_event(type)
    source_store.read(
      streams.history_migration(migration_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ type ],
        maximum_count: 1,
        direction: :asc
      )
    ).sole
  end

  def latest_migration_event(type)
    source_store.read_latest(
      streams.history_migration(migration_id),
      Coordinator::Write::LatestEventReadCriteria.new(event_types: [ type ])
    )
  end

  def page_stream(page_id)
    source_store.read(
      streams.history_migration_page(page_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: Coordinator::Write::HistoryMigrations::PageLoader::EVENT_TYPES,
        maximum_count: Coordinator::Write::HistoryMigrations::PageLoader::MAXIMUM_EVENT_COUNT,
        direction: :asc
      )
    )
  end
end
