# frozen_string_literal: true

RSpec.describe Coordinator::Write::HistoryMigrations::PostRemodelContractCatalog do
  subject(:catalog) { described_class.new }

  it "freezes the complete post-remodel delta observed before MIGRATION-01 planning" do
    expect(catalog.source_contracts.size).to eq(49)
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
