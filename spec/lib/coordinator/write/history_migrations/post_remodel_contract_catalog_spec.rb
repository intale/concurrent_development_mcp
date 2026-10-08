# frozen_string_literal: true

RSpec.describe Coordinator::Write::HistoryMigrations::PostRemodelContractCatalog do
  subject(:catalog) { described_class.new }

  it "freezes the reviewed post-remodel contracts used by migration and replay" do
    expect(catalog.source_contracts.size).to eq(56)
    expect(catalog).to be_include(type: "RepositoryRegistered", schema_version: 2)
    expect(catalog.source_contracts.uniq).to eq(catalog.source_contracts)
    expect(catalog).to be_include(type: "AttemptAuthorized", schema_version: 2)
    expect(catalog).to be_include(type: "DevelopmentArtifactContentChanged", schema_version: 1)
    expect(catalog).to be_include(type: "ResourceWorkIntentionDeclared", schema_version: 1)
  end

  it "does not reinterpret any frozen pre-remodel contract" do
    legacy = Coordinator::Write::HistoryMigrations::LegacyContractCatalog::SOURCE_CONTRACTS

    expect(catalog.source_contracts & legacy).to be_empty
  end
end
