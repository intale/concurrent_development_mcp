# frozen_string_literal: true

RSpec.describe Coordinator::Shared::Observability::SettingsLoader do
  subject(:loader) { described_class.new }

  it "defaults to disabled telemetry with direct development OTLP endpoints" do
    settings = loader.call(environment: "development", env: {})

    expect(settings.enabled).to be(false)
    expect(settings.mode).to eq("otlp")
    expect(settings.traces_endpoint).to eq("http://localhost:4318/v1/traces")
    expect(settings.metrics_endpoint).to eq("http://localhost:9090/api/v1/otlp/v1/metrics")
    expect(settings.export_timeout_ms).to eq(3000)
    expect(settings).to be_frozen
  end

  it "forces the official in-memory adapters in test, even with network endpoints configured" do
    settings = loader.call(environment: "test", env: {
      "COORDINATOR_OBSERVABILITY_ENABLED" => "true",
      "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT" => "http://tempo:4318/v1/traces",
      "OTEL_EXPORTER_OTLP_METRICS_ENDPOINT" => "http://prometheus:9090/api/v1/otlp/v1/metrics"
    })

    expect(settings.enabled).to be(true)
    expect(settings.mode).to eq("in_memory")
  end

  it "validates and coerces bounded exporter settings with dry-rb" do
    settings = loader.call(environment: "production", env: {
      "COORDINATOR_OBSERVABILITY_ENABLED" => "1",
      "COORDINATOR_OBSERVABILITY_ROLE" => "read_models",
      "OTEL_METRIC_EXPORT_INTERVAL" => "2000",
      "COORDINATOR_OBSERVABILITY_TRACE_SAMPLE_RATIO" => "0.25"
    })

    expect(settings.export_interval_ms).to eq(2000)
    expect(settings.trace_sample_ratio).to eq(0.25)
    expect(settings.role).to eq("read_models")
  end

  it "rejects unsafe endpoints without echoing their secrets" do
    expect do
      loader.call(environment: "production", env: {
        "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT" => "http://user:secret@tempo:4318/v1/traces"
      })
    end.to raise_error(ArgumentError, "Invalid observability settings: traces_endpoint")
  end

  it "rejects invalid intervals and unsupported roles" do
    expect do
      loader.call(environment: "production", env: {
        "OTEL_METRIC_EXPORT_INTERVAL" => "0", "COORDINATOR_OBSERVABILITY_ROLE" => "secret-user-id"
      })
    end.to raise_error(ArgumentError, /Invalid observability settings/)
  end
end
