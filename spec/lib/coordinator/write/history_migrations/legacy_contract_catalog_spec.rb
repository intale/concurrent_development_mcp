# frozen_string_literal: true

RSpec.describe Coordinator::Write::HistoryMigrations::LegacyContractCatalog do
  subject(:catalog) { described_class.new }

  it "freezes the complete EM-05 source contract set" do
    expect(catalog.source_contracts.size).to eq(108)
    expect(catalog.source_contracts.uniq).to eq(catalog.source_contracts)
    expect(catalog).to be_include(type: "RepositoryRegistered", schema_version: 1)
    expect(catalog).to be_include(type: "WriteSetReleased", schema_version: 2)
    expect(catalog).not_to be_include(type: "RepositoryRegistered", schema_version: 2)
  end
end
