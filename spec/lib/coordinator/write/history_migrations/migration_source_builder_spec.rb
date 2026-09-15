# frozen_string_literal: true

RSpec.describe Coordinator::Write::HistoryMigrations::MigrationSourceBuilder, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }

  it "captures source identity and physical event time without copying payload" do
    source = event_store.append(
      Coordinator::Write::StreamReference.new(
        context: "LegacyDevelopmentPlanning",
        stream_name: "Repository",
        stream_id: "legacy-repository"
      ),
      [
        PgEventstore::Event.new(
          id: SecureRandom.uuid_v7,
          type: "RepositoryRegistered",
          data: { "large_dump" => "must not enter provenance" },
          metadata: { "schema_version" => 1 },
          correlation_id: SecureRandom.uuid_v7
        )
      ]
    ).sole

    provenance = described_class.new.call(config_name: "default", event: source)

    expect(provenance).to have_attributes(
      event_id: source.id,
      event_type: "RepositoryRegistered",
      schema_version: 1,
      stream_id: "legacy-repository",
      stream_revision: 0,
      global_position: source.global_position,
      created_at: source.created_at.utc.iso8601(6),
      correlation_id: source.correlation_id
    )
    expect(provenance.to_h).not_to have_key(:data)
    expect(provenance.to_h.to_s).not_to include("large_dump")
  end
end
