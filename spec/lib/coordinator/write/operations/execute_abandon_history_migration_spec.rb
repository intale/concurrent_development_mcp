# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteAbandonHistoryMigration, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:stream) { Coordinator::Write::StreamFactory.new.history_migration(migration_id) }
  let(:operation) { described_class.new(event_store:) }
  let(:command) do
    Coordinator::Write::Commands::AbandonHistoryMigration.new(
      command_id: "abandon-duplicate-history-migration",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "migration-operator"),
      migration_id:,
      reason: "Accidental duplicate of the intended migration"
    )
  end

  before do
    result = Coordinator::Write::Operations::ExecuteStartHistoryMigration.new(event_store:).call_command(
      Coordinator::Write::Commands::StartHistoryMigration.new(
        command_id: "start-history-migration",
        actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "migration-operator"),
        migration_id:,
        source_config_name: "default",
        target_config_name: "migration_target",
        source_upper_position: 9,
        page_size: 10
      )
    )
    expect(result).to be_success
  end

  it "appends an idempotent terminal abandonment fact with optimistic concurrency" do
    first = operation.call_command(command)
    replay = operation.call_command(command)

    expect(first).to be_success
    expect(replay).to be_success
    expect(replay.value!.id).to eq(first.value!.id)
    expect(first.value!).to have_attributes(
      type: "HistoryMigrationAbandoned",
      stream_revision: 6,
      correlation_id: match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    )
    expect(first.value!.data).to include(
      "migration_id" => migration_id,
      "reason" => "Accidental duplicate of the intended migration"
    )
    expect(first.value!.markers).to include(
      "history-migration:#{migration_id}",
      "command:abandon-duplicate-history-migration"
    )

    migration = Coordinator::Write::HistoryMigrations::MigrationLoader.new(event_store:).call(migration_id)
    expect(migration).to be_abandoned
    expect(migration).not_to be_completed
    expect(migration.latest_revision).to eq(6)
  end
end
