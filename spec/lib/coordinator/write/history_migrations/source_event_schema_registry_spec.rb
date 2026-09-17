# frozen_string_literal: true

RSpec.describe Coordinator::Write::HistoryMigrations::SourceEventSchemaRegistry do
  subject(:registry) { described_class.new }

  it "owns exactly the frozen pre-remodel and post-remodel source schemas" do
    expected = [
      *Coordinator::Write::HistoryMigrations::LegacyContractCatalog::SOURCE_CONTRACTS,
      *Coordinator::Write::HistoryMigrations::PostRemodelContractCatalog::SOURCE_CONTRACTS
    ]

    expect(described_class::DEFINITIONS.keys).to match_array(expected)
    expect(expected.map { |type, schema_version| registry.fetch(type:, schema_version:) }).to all(
      be < Coordinator::Write::Events::Base
    )
  end

  it "loads both removed legacy payloads and post-remodel payloads" do
    legacy = registry.load(
      type: "CoordinationTaskExecutionStarted",
      schema_version: 1,
      data: {
        "task_id" => "018f0f4d-4e45-7abc-8def-000000000901",
        "started_at" => "2026-08-01T12:00:00.000000Z"
      }
    )
    current = registry.load(
      type: "AttemptAuthorized",
      schema_version: 2,
      data: { "attempt_id" => "018f0f4d-4e45-7abc-8def-000000000902" }
    )

    expect(legacy).to be_a(
      Coordinator::Write::HistoryMigrations::LegacyEvents::CoordinationTaskExecutionStartedV1
    )
    expect(current).to be_a(Coordinator::Write::Events::AttemptAuthorizedV2)
  end
end
