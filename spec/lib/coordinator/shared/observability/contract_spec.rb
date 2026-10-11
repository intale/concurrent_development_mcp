# frozen_string_literal: true

RSpec.describe Coordinator::Shared::Observability::Contract do
  it "defines distinct attempts, completions, runtime, delivery age and unfinished age" do
    metrics = described_class.metrics.index_by(&:key)

    expect(metrics.keys).to contain_exactly(
      :mcp_started, :mcp_completed, :mcp_duration, :mcp_in_flight,
      :subscription_started, :subscription_completed, :subscription_duration,
      :subscription_in_flight, :subscription_oldest_in_flight, :subscription_delivery_age,
      :sql_completed, :sql_duration
    )
    expect(metrics[:subscription_oldest_in_flight].kind).to eq(:observable_gauge)
    expect(metrics[:subscription_delivery_age].boundaries).to eq(described_class::AGE_BOUNDARIES)
    expect(metrics[:subscription_duration].boundaries).to eq(described_class::DURATION_BOUNDARIES)
    expect(metrics.values.select { _1.kind == :histogram }.map(&:unit)).to all(eq("s"))
    expect(metrics.values).to all(be_frozen)
    expect(metrics.values.map(&:name).uniq.length).to eq(metrics.length)
  end

  it "allows only low-cardinality dimensions, never caller identifiers or SQL" do
    allowed = %w[rpc.method mcp.tool.name subscription.set subscription.name event.type db.operation.name outcome]

    expect(described_class.metrics.flat_map(&:dimensions).uniq).to match_array(allowed)
    described_class.metrics.each do |metric|
      expect(metric.boundaries).to eq(metric.boundaries.sort.uniq)
    end
  end

  it "separates acceptance and returned business outcomes and bounds unknown outcomes" do
    %w[accepted denied invalid not_found not_modified command_id_reused conflict busy limit_reached pending cancelled error].each do |outcome|
      expect(described_class.outcome(outcome)).to eq(outcome)
    end
    expect(described_class.outcome("caller-controlled-payload")).to eq("unknown")
    expect(described_class.outcome(nil)).to eq("unknown")
  end
end
