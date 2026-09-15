# frozen_string_literal: true

RSpec.describe Coordinator::Write::HistoryMigrations::RepositoryRegisteredV1Transformer, :event_store do
  subject(:transformer) do
    described_class.new(
      stream_identity_allocator: Coordinator::Write::HistoryMigrations::StreamIdentityAllocator.new(event_store:)
    )
  end

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:source_payload) do
    Coordinator::Write::Events::RepositoryRegisteredV1.new(
      repository_id: SecureRandom.uuid_v7,
      scope: "project:legacy",
      repository_key: "legacy-app",
      display_name: "Legacy app",
      paths: [ "/workspace/legacy" ],
      remotes: [ "git@example.test:legacy/app.git" ],
      registered_at: "2026-01-01T12:00:00.000000Z"
    )
  end
  let(:source_event) do
    event_store.append(
      Coordinator::Write::StreamReference.new(
        context: "LegacyDevelopmentPlanning",
        stream_name: "Repository",
        stream_id: "repository:v1:#{'b' * 64}"
      ),
      [
        PgEventstore::Event.new(
          id: SecureRandom.uuid_v7,
          type: "RepositoryRegistered",
          data: source_payload.to_h,
          metadata: { "schema_version" => 1 },
          correlation_id: SecureRandom.uuid_v7
        )
      ]
    ).sole
  end

  it "decomposes a legacy registration dump into cohesive facts on one allocated UUIDv7 stream" do
    result = transformer.call(
      migration_id: SecureRandom.uuid_v7,
      source_config_name: "default",
      source_event:,
      source_payload:
    )

    expect(result).to be_success
    facts = result.value!
    expect(facts.map { _1.event.class }).to eq(
      [
        Coordinator::Write::Events::RepositoryRegisteredV2,
        Coordinator::Write::Events::RepositoryDisplayNameChangedV1,
        Coordinator::Write::Events::RepositoryPathAddedV1,
        Coordinator::Write::Events::RepositoryRemoteAddedV1
      ]
    )
    expect(facts.map(&:target_stream).uniq.one?).to be(true)
    expect(facts.first.target_stream.stream_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(facts.map { _1.event.to_h }.to_s).not_to include("registered_at")
    expect(facts.first.markers.grep(/scoped-repository-key/).one?).to be(true)
    expect(facts.flat_map(&:markers)).not_to include(match(/#{'b' * 32}/))
  end
end
