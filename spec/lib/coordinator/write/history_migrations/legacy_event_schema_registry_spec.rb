# frozen_string_literal: true

RSpec.describe Coordinator::Write::HistoryMigrations::LegacyEventSchemaRegistry do
  subject(:registry) { described_class.new }

  it "owns a schema for every frozen legacy source contract" do
    contracts = Coordinator::Write::HistoryMigrations::LegacyContractCatalog.new.source_contracts

    expect(described_class::DEFINITIONS.keys).to match_array(contracts)
    expect(contracts.map { |type, schema_version| registry.fetch(type:, schema_version:) }).to all(be < Coordinator::Write::Events::Base)
  end

  it "deserializes contracts removed from the live write model" do
    payload = registry.load(
      type: "CoordinationTaskExecutionStarted",
      schema_version: 1,
      data: {
        "task_id" => "018f0f4d-4e45-7abc-8def-000000000901",
        "started_at" => "2026-08-01T12:00:00.000000Z"
      }
    )

    expect(payload).to be_a(
      Coordinator::Write::HistoryMigrations::LegacyEvents::CoordinationTaskExecutionStartedV1
    )
    expect(payload.task_id).to eq("018f0f4d-4e45-7abc-8def-000000000901")
  end

  it "does not make removed contracts part of the live schema registry" do
    expect do
      Coordinator::Write::EventSchemaRegistry.new.fetch(
        type: "CoordinationTaskExecutionStarted",
        schema_version: 1
      )
    end.to raise_error(Coordinator::Write::EventSchemaRegistry::UnknownSchema)
  end
end
