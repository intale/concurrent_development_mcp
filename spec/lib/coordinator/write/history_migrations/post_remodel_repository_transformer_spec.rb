# frozen_string_literal: true

RSpec.describe Coordinator::Write::HistoryMigrations::PostRemodelRepositoryTransformer, :event_store do
  subject(:transformer) do
    described_class.new(
      event_store: store,
      stream_identity_allocator: Coordinator::Write::HistoryMigrations::StreamIdentityAllocator.new(event_store: store)
    )
  end

  let(:store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:source_id) { SecureRandom.uuid_v7 }
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:registration) do
    Coordinator::Write::Events::RepositoryRegisteredV2.new(repository_id: source_id, scope: "project:replay", repository_key: "application")
  end

  it "remaps current registration and descriptive facts onto the same allocated stream" do
    registered = persist(registration)
    name = Coordinator::Write::Events::RepositoryDisplayNameChangedV1.new(repository_id: source_id, display_name: "Application")
    renamed = persist(name)

    facts = [ [ registered, registration ], [ renamed, name ] ].map do |event, payload|
      transformer.call(
        migration_id:, source_config_name: "default", source_upper_position: renamed.global_position,
        source_event: event, source_payload: payload
      ).value!.sole
    end

    expect(facts.map(&:target_stream).uniq.length).to eq(1)
    expect(facts.map { _1.event.repository_id }.uniq).to eq([ facts.first.target_stream.stream_id ])
    expect(facts.first.target_stream.stream_id).not_to eq(source_id)
    expect(facts.first.event.to_h).to include(scope: "project:replay", repository_key: "application")
    expect(facts.last.event.display_name).to eq("Application")
    expect(facts.first.markers).to include(Coordinator::Write::Repositories::NaturalKeyMarker.new.call(scope: "project:replay", repository_key: "application").marker)
  end

  it "rejects a source payload whose identity disagrees with the persisted stream" do
    event = persist(registration)
    invalid = registration.class.new(registration.to_h.merge(repository_id: SecureRandom.uuid_v7))

    result = transformer.call(
      migration_id:, source_config_name: "default", source_upper_position: event.global_position,
      source_event: event, source_payload: invalid
    )

    expect(result).to be_failure
    expect(result.failure.code).to eq(:ambiguous_source_reference)
  end

  def persist(payload)
    store.append(
      Coordinator::Write::StreamFactory.new.repository(source_id),
      [ Coordinator::Write::EventFactory.new.build!(
        event: payload, event_id: SecureRandom.uuid_v7,
        metadata: Coordinator::Write::EventMetadata.new(
          command_id: SecureRandom.uuid_v7, actor_kind: "agent", actor_id: "migration-agent",
          recorded_by: "coordinator", policy_version: "repository-registration/v1"
        ), markers: [ "repository:#{source_id}" ], correlation_id: SecureRandom.uuid_v7
      ) ]
    ).sole
  end
end
