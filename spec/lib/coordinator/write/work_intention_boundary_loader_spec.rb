# frozen_string_literal: true

RSpec.describe Coordinator::Write::WorkIntentionBoundaryLoader, :event_store do
  subject(:loader) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:repository_id) { SecureRandom.uuid_v7 }
  let(:marker) { "resource-boundary:#{repository_id}:file:lib/example.rb" }
  let(:at) { "2026-10-09T09:00:00.000000Z" }

  it "starts an absent boundary at epoch zero without inventing a source event" do
    boundary = loader.call([ marker ], repository_id:, at:).value!

    expect(boundary.epochs.sole).to have_attributes(epoch: 0, event: nil, through_global_position: nil)
    expect(boundary.delta_event_count).to eq(0)
  end

  it "loads the current lean epoch and preserves its exact persisted source" do
    persisted = append_epoch(schema_version: 3)
    boundary = loader.call([ marker ], repository_id:, at:).value!

    expect(boundary.epochs.sole).to have_attributes(
      epoch: 1, through_global_position: 0,
      event: have_attributes(id: persisted.id, type: "ResourceBoundaryEpochRolled")
    )
    expect(boundary.active_observations).to eq([])
  end

  it "rejects a retired snapshot schema instead of silently treating it as an absent boundary" do
    append_epoch(schema_version: 2)

    expect { loader.call([ marker ], repository_id:, at:) }
      .to raise_error(Coordinator::Write::EventSchemaRegistry::UnknownSchema)
  end

  def append_epoch(schema_version:)
    event_store.append(
      Coordinator::Write::StreamReference.new(
        context: "DevelopmentCoordination", stream_name: "ResourceBoundaryEpoch", stream_id: repository_id
      ),
      [
        PgEventstore::Event.new(
          id: SecureRandom.uuid_v7, type: "ResourceBoundaryEpochRolled",
          data: { "repository_id" => repository_id, "boundary_marker" => marker,
                  "epoch" => 1, "through_global_position" => 0 },
          metadata: { "schema_version" => schema_version }, markers: [ marker ]
        )
      ]
    ).sole
  end
end
