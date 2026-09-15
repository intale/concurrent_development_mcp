# frozen_string_literal: true

RSpec.describe Coordinator::Write::HistoryMigrations::StreamIdentityAllocator, :event_store do
  subject(:allocator) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:source_event) do
    reference = Coordinator::Write::StreamReference.new(
      context: "LegacyDevelopmentKnowledge",
      stream_name: "DevelopmentArtifact",
      stream_id: "artifact:v1:#{'a' * 64}"
    )
    persisted = event_store.append(
      reference,
      [ PgEventstore::Event.new(id: SecureRandom.uuid_v7, type: "LegacyArtifactObserved") ]
    ).sole
    PgEventstore.client.read(
      PgEventstore::Stream.new(**reference.to_h),
      options: { direction: :asc, from_revision: persisted.stream_revision, max_count: 1 }
    ).sole
  end

  it "allocates one UUIDv7 stream identity from a non-digest indexed selector" do
    first = allocation("artifact")
    replay = allocation("artifact")
    second_role = allocation("artifact-observation")

    expect(first).to be_success
    expect(replay).to be_success
    expect(second_role).to be_success
    expect(first.value!.outcome).to eq("created")
    expect(replay.value!.outcome).to eq("existing")
    expect(replay.value!.target_stream).to eq(first.value!.target_stream)
    expect(first.value!.target_stream.stream_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(second_role.value!.target_stream.stream_id).not_to eq(first.value!.target_stream.stream_id)

    marker = first.value!.allocation_event.markers.find { _1.start_with?("compound:history-migration-stream:v2") }
    expect(marker).to include("source-position=")
    expect(marker).not_to include(source_event.stream.stream_id)
    expect(identity_events(first.value!.target_stream.stream_id).length).to eq(1)
  end

  private

  def allocation(role)
    allocator.call(
      migration_id:,
      source_config_name: "default",
      source_event:,
      target_stream_context: "DevelopmentKnowledge",
      target_stream_name: "DevelopmentArtifact",
      identity_role: role
    )
  end

  def identity_events(identity)
    event_store.read(
      streams.history_migration_identity(identity),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "HistoryMigrationStreamIdentityAllocated" ],
        maximum_count: 1,
        direction: :asc
      )
    )
  end
end
