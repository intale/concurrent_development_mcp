# frozen_string_literal: true

RSpec.describe Coordinator::Write::HistoryMigrations::TransformerRegistry, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:registry) { Coordinator::Container["history_migrations.transformer_registry"] }

  it "registers every frozen pre-remodel and post-remodel source contract" do
    expect(registry.registered_contracts).to match_array(
      [
        *Coordinator::Write::HistoryMigrations::LegacyContractCatalog::SOURCE_CONTRACTS,
        *Coordinator::Write::HistoryMigrations::PostRemodelContractCatalog::SOURCE_CONTRACTS
      ]
    )
  end

  it "fails closed when a registered source contract has an invalid payload" do
    source = PgEventstore::Event.new(
      id: SecureRandom.uuid_v7,
      type: "DevelopmentArtifactContentChanged",
      data: {},
      metadata: { "schema_version" => 1 }
    )

    result = registry.call(
      migration_id: SecureRandom.uuid_v7,
      source_config_name: "default",
      source_upper_position: 0,
      source_event: source
    )

    expect(result).to be_failure
    expect(result.failure).to have_attributes(
      code: :invalid_source_event,
      event_type: "DevelopmentArtifactContentChanged",
      schema_version: 1
    )
  end

  it "fails closed when a source contract has no reviewed mapping" do
    source = PgEventstore::Event.new(
      id: SecureRandom.uuid_v7,
      type: "UnreviewedLegacyFact",
      data: {},
      metadata: { "schema_version" => 7 }
    )

    result = registry.call(
      migration_id: SecureRandom.uuid_v7,
      source_config_name: "default",
      source_upper_position: 0,
      source_event: source
    )

    expect(result).to be_failure
    expect(result.failure).to have_attributes(
      code: :unsupported_source_contract,
      event_type: "UnreviewedLegacyFact",
      schema_version: 7,
      source_event_id: source.id
    )
  end
end
