# frozen_string_literal: true

RSpec.describe Coordinator::Write::HistoryMigrations::TargetStreamPlanAllocator, :event_store do
  subject(:allocator) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:target_stream) do
    Coordinator::Write::StreamReference.new(
      context: "DevelopmentPlanning",
      stream_name: "Repository",
      stream_id: SecureRandom.uuid_v7
    )
  end
  let(:caused_by) do
    source_stream = Coordinator::Write::StreamReference.new(
      context: "CoordinatorMaintenance",
      stream_name: "HistoryMigration",
      stream_id: migration_id
    )
    event_store.append(
      source_stream,
      [ PgEventstore::Event.new(id: SecureRandom.uuid_v7, type: "HistoryMigrationStarted") ]
    ).sole
  end

  it "finds or creates one UUIDv7 planning stream per migration and target stream" do
    first = allocator.call(migration_id:, target_stream:, caused_by:)
    replay = allocator.call(migration_id:, target_stream:, caused_by:)

    expect(first).to be_success
    expect(replay).to be_success
    expect(first.value!.outcome).to eq("created")
    expect(replay.value!.outcome).to eq("existing")
    expect(replay.value!.plan_stream).to eq(first.value!.plan_stream)
    expect(first.value!.plan_stream.stream_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(first.value!.target_stream).to eq(target_stream)

    marker = first.value!.allocation_event.markers.find do
      _1.start_with?("compound:history-migration-target-stream-plan:v2")
    end
    expect(marker).to include("target-id=")
    expect(marker).not_to match(/sha|md5/i)
  end

  it "allocates a separate plan for the same target in another migration" do
    first = allocator.call(migration_id:, target_stream:, caused_by:)
    another_migration_id = SecureRandom.uuid_v7
    another_cause = PgEventstore::Event.new(
      id: SecureRandom.uuid_v7,
      type: "HistoryMigrationStarted",
      correlation_id: caused_by.correlation_id
    )
    second = allocator.call(
      migration_id: another_migration_id,
      target_stream:,
      caused_by: another_cause
    )

    expect(second).to be_success
    expect(second.value!.plan_stream).not_to eq(first.value!.plan_stream)
  end
end
