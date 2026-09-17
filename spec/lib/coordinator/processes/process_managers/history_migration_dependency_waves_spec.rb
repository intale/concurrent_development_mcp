# frozen_string_literal: true

RSpec.describe "history migration dependency waves", :event_store do
  let(:source_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:target_client) { PgEventstore.client(:migration_target) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:manager) { Coordinator::Container["process_managers.history_migration"] }
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:repository_id) { SecureRandom.uuid_v7 }
  let(:change_set_id) { "legacy-change-set" }
  let(:work_item_id) { "legacy-work-item" }

  it "creates every endpoint before applying a relation from an earlier source page" do
    source_upper_position = append_legacy_history
    pages, application_source = plan_history(source_upper_position:)

    4.times do |dependency_wave|
      pages.each do |page_id|
        manager.call(application_source)
        wave_event = page_stream(page_id).select do |event|
          event.type == "HistoryMigrationPageDependencyWaveApplied"
        end.fetch(dependency_wave)
        manager.call(wave_event)
        application_source = latest_migration_event("HistoryMigrationApplicationCursorAdvanced")
      end
    end
    manager.call(application_source)

    migration = Coordinator::Container["history_migrations.migration_loader"].call(migration_id)
    expect(migration).to be_completed

    persisted = target_client.read(
      PgEventstore::Stream.all_stream,
      options: {
        direction: :asc,
        max_count: 20,
        filter: {
          event_types: %w[RepositoryRegistered WorkItemCreated WorkItemAssignedToRepository]
        }
      }
    )
    repository = persisted.find { _1.type == "RepositoryRegistered" }
    work_item = persisted.find { _1.type == "WorkItemCreated" }
    assignment = persisted.find { _1.type == "WorkItemAssignedToRepository" }

    expect(repository.global_position).to be < assignment.global_position
    expect(work_item.global_position).to be < assignment.global_position
  end

  private

  def append_legacy_history
    append(
      stream("DevelopmentExecution", "WorkItem", work_item_id),
      Coordinator::Write::Events::WorkItemCreatedV1.new(
        work_item_id:,
        change_set_id:,
        repository_id:,
        goal: "Migrate dependency order",
        acceptance_criteria: [ "Relations follow endpoint creation" ],
        competitive_mode: false,
        created_at: "2026-01-01T12:00:00.000000Z"
      )
    )
    append(
      stream("DevelopmentPlanning", "ChangeSet", change_set_id),
      Coordinator::Write::Events::ChangeSetCreatedV1.new(
        change_set_id:,
        goal: "Migrate dependency order",
        created_at: "2026-01-01T12:01:00.000000Z"
      )
    )
    append(
      stream("DevelopmentPlanning", "Repository", repository_id),
      Coordinator::Write::Events::RepositoryRegisteredV1.new(
        repository_id:,
        scope: "project:legacy",
        repository_key: "legacy-app",
        display_name: nil,
        paths: [],
        remotes: [],
        registered_at: "2026-01-01T12:02:00.000000Z"
      )
    ).global_position
  end

  def append(stream_reference, payload)
    source_store.append(
      stream_reference,
      [
        PgEventstore::Event.new(
          id: SecureRandom.uuid_v7,
          type: payload.class.event_type,
          data: payload.to_h,
          metadata: { "schema_version" => payload.class.schema_version },
          correlation_id: SecureRandom.uuid_v7
        )
      ]
    ).sole
  end

  def plan_history(source_upper_position:)
    checkpoint = start_migration(through: source_upper_position)
    pages = []
    loop do
      manager.call(checkpoint)
      source_count = page_events("HistoryMigrationPageSourceEventCountRecorded").last
      page_id = source_count.stream.stream_id
      pages << page_id
      manager.call(source_count)
      planned = page_stream(page_id).last
      expect(planned.type).to eq("HistoryMigrationPagePlanned")
      manager.call(planned)
      checkpoint = latest_migration_checkpoint
      break if checkpoint.type == "HistoryMigrationPlanCompleted"
    end

    [ pages, checkpoint ]
  end

  def start_migration(through:)
    result = Coordinator::Write::Operations::ExecuteStartHistoryMigration.new(event_store: source_store)
      .call_command(
        Coordinator::Write::Commands::StartHistoryMigration.new(
          command_id: "history-migration-dependency-wave-test",
          actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "test-agent"),
          migration_id:,
          source_config_name: "default",
          target_config_name: "migration_target",
          source_upper_position: through,
          page_size: 1
        )
      )
    expect(result).to be_success
    latest_migration_event("HistoryMigrationStarted")
  end

  def page_events(type)
    source_store.read_global_marked(
      Coordinator::Write::GlobalMarkedEventReadCriteria.new(
        stream_context: "CoordinatorMaintenance",
        stream_name: "HistoryMigrationPage",
        event_types: [ type ],
        markers: [ "history-migration:#{migration_id}" ],
        maximum_count: 10,
        direction: :asc
      )
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

  def latest_migration_checkpoint
    source_store.read_latest(
      streams.history_migration(migration_id),
      Coordinator::Write::LatestEventReadCriteria.new(
        event_types: %w[HistoryMigrationCursorAdvanced HistoryMigrationPlanCompleted]
      )
    )
  end

  def latest_migration_event(type)
    source_store.read_latest(
      streams.history_migration(migration_id),
      Coordinator::Write::LatestEventReadCriteria.new(event_types: [ type ])
    )
  end

  def stream(context, stream_name, stream_id)
    Coordinator::Write::StreamReference.new(context:, stream_name:, stream_id:)
  end
end
