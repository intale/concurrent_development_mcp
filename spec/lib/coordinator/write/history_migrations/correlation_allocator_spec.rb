# frozen_string_literal: true

RSpec.describe Coordinator::Write::HistoryMigrations::CorrelationAllocator, :event_store do
  subject(:allocator) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:source_correlation_id) { SecureRandom.uuid_v7 }

  it "allocates one UUIDv7 target correlation for a source trace" do
    first_source = append_source(correlation_id: source_correlation_id)
    second_source = append_source(correlation_id: source_correlation_id)

    first = allocate(first_source)
    replay = allocate(second_source)

    expect(first).to be_success
    expect(replay).to be_success
    expect(first.value!.outcome).to eq("created")
    expect(replay.value!.outcome).to eq("existing")
    expect(replay.value!.target_correlation_id).to eq(first.value!.target_correlation_id)
    expect(first.value!.target_correlation_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)

    marker = first.value!.allocation_event.markers.find do
      _1.start_with?("compound:history-migration-correlation:v2")
    end
    expect(marker).to include("source-correlation=")
    expect(marker).not_to match(/sha|md5/i)
  end

  it "uses the native correlation assigned to a source event without an explicit correlation" do
    source = append_source(correlation_id: nil)
    first = allocate(source)
    replay = allocate(source)

    expect(replay.value!.target_correlation_id).to eq(first.value!.target_correlation_id)
    marker = first.value!.allocation_event.markers.find do
      _1.start_with?("compound:history-migration-correlation:v2")
    end
    expect(source.correlation_id).to be_present
    expect(marker).to include("source-correlation=")
  end

  private

  def append_source(correlation_id:)
    reference = Coordinator::Write::StreamReference.new(
      context: "LegacyDevelopmentPlanning",
      stream_name: "Repository",
      stream_id: SecureRandom.uuid_v7
    )
    event_store.append(
      reference,
      [
        PgEventstore::Event.new(
          id: SecureRandom.uuid_v7,
          type: "LegacyRepositoryRegistered",
          correlation_id:
        )
      ]
    ).sole
  end

  def allocate(source_event)
    allocator.call(migration_id:, source_config_name: "default", source_event:)
  end
end
