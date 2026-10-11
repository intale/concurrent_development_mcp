# frozen_string_literal: true

RSpec.describe "observability Compose configuration" do
  def telemetry_compose(filename, overrides = {})
    environment = {
      "PRODUCTION_ENV_FILE" => "/dev/null", "POSTGRES_PASSWORD" => "configuration-test", "SECRET_KEY_BASE" => "configuration-test",
      "GRAFANA_ADMIN_PASSWORD" => "configuration-test", "GRAFANA_ADMIN_USER" => nil, "GRAFANA_HOST_PORT" => nil,
      "PROMETHEUS_HOST_PORT" => nil, "TEMPO_OTLP_HOST_PORT" => nil, "PROMETHEUS_RETENTION_TIME" => nil,
      "PROMETHEUS_RETENTION_SIZE" => nil, "TEMPO_RETENTION" => nil, "COORDINATOR_OBSERVABILITY_ENABLED" => nil,
      "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT" => nil, "OTEL_EXPORTER_OTLP_METRICS_ENDPOINT" => nil
    }.merge(overrides)
    output, error, status = Open3.capture3(environment, "docker", "compose", "--env-file", "/dev/null",
                                          "-f", Rails.root.join(filename).to_s, "config", "--format", "json")
    expect(status).to be_success, error
    JSON.parse(output)
  end

  def provisioned_yaml(path)
    YAML.safe_load_file(Rails.root.join("config/observability", path))
  end

  it "configures retention under the pinned Tempo 3 backend worker instead of an invalid root key" do
    tempo = provisioned_yaml("tempo.yml")
    expect(tempo.dig("backend_worker", "compaction", "block_retention")).to eq("${TEMPO_RETENTION:-168h}")
    expect(tempo).not_to have_key("compaction")
    expect(tempo).not_to have_key("compactor")
  end

  it "pins three directly connected backends and gives each independent persistent storage" do
    %w[docker-compose.yml docker-compose.production.yml].each do |filename|
      configuration = telemetry_compose(filename)
      services = configuration.fetch("services")
      { "prometheus" => "prom/prometheus:v3.13.4", "tempo" => "grafana/tempo:3.1.0", "grafana" => "grafana/grafana:13.2.3" }.each do |name, image|
        expect(services.dig(name, "image")).to eq(image)
        expect(services.dig(name, "volumes")).to include(include("type" => "volume", "source" => "#{name}_data"))
        expect(configuration.fetch("volumes")).to have_key("#{name}_data")
      end
      expect(services).not_to have_key("collector")
      expect(services.dig("prometheus", "command")).to include("--web.enable-otlp-receiver", "--storage.tsdb.retention.time=15d", "--storage.tsdb.retention.size=10GB")
      expect(services.dig("prometheus", "command")).not_to include("--web.enable-admin-api")
      expect(services.dig("tempo", "command")).to include("-target=all", "-config.expand-env=true")
    end
  end

  it "publishes development ingestion and loopback-only Grafana on 1089" do
    services = telemetry_compose("docker-compose.yml").fetch("services")
    expect(services.dig("prometheus", "ports")).to include(include("published" => "9090", "target" => 9090))
    expect(services.dig("tempo", "ports")).to include(include("published" => "4318", "target" => 4318))
    expect(services.dig("grafana", "ports")).to include(include("host_ip" => "127.0.0.1", "published" => "1089", "target" => 3000))
  end

  it "keeps production ingestion internal and publishes only Grafana on loopback 8089" do
    services = telemetry_compose("docker-compose.production.yml").fetch("services")
    %w[prometheus tempo].each { expect(services.fetch(_1).fetch("ports", [])).to be_empty }
    expect(services.dig("grafana", "ports")).to include(include("host_ip" => "127.0.0.1", "published" => "8089", "target" => 3000))
    roles = { "web" => "web", "subscription-process-managers" => "process_managers", "subscription-task-results" => "task_results",
              "subscription-read-models" => "read_models", "jobs" => "jobs" }
    roles.each do |name, role|
      expect(services.dig(name, "environment")).to include(
        "COORDINATOR_OBSERVABILITY_ENABLED" => "true", "COORDINATOR_OBSERVABILITY_ROLE" => role,
        "OTEL_EXPORTER_OTLP_METRICS_ENDPOINT" => "http://prometheus:9090/api/v1/otlp/v1/metrics",
        "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT" => "http://tempo:4318/v1/traces"
      )
      expect(services.fetch(name).fetch("depends_on").keys & %w[prometheus tempo grafana]).to be_empty
    end
    expect(services.dig("prepare", "environment", "COORDINATOR_OBSERVABILITY_ENABLED")).to eq("false")
  end

  it "honors explicit telemetry and retention settings without changing port binding policy" do
    services = telemetry_compose("docker-compose.production.yml", {
      "COORDINATOR_OBSERVABILITY_ENABLED" => "false", "GRAFANA_HOST_PORT" => "18089",
      "PROMETHEUS_RETENTION_TIME" => "3d", "PROMETHEUS_RETENTION_SIZE" => "2GB", "TEMPO_RETENTION" => "48h",
      "OTEL_EXPORTER_OTLP_METRICS_ENDPOINT" => "http://custom-metrics:9090/api/v1/otlp/v1/metrics"
    }).fetch("services")
    expect(services.dig("web", "environment", "COORDINATOR_OBSERVABILITY_ENABLED")).to eq("false")
    expect(services.dig("web", "environment", "OTEL_EXPORTER_OTLP_METRICS_ENDPOINT")).to start_with("http://custom-metrics:")
    expect(services.dig("prometheus", "command")).to include("--storage.tsdb.retention.time=3d", "--storage.tsdb.retention.size=2GB")
    expect(services.dig("tempo", "environment", "TEMPO_RETENTION")).to eq("48h")
    expect(services.dig("grafana", "ports")).to include(include("host_ip" => "127.0.0.1", "published" => "18089"))
  end

  it "provisions compatible cumulative metric translation and finite resource labels" do
    otlp = provisioned_yaml("prometheus.yml").fetch("otlp")
    expect(otlp.fetch("translation_strategy")).to eq("UnderscoreEscapingWithSuffixes")
    expect(otlp.fetch("promote_resource_attributes")).to match_array(%w[
      service.name service.instance.id service.version deployment.environment.name coordinator.process.role
    ])
    expect(provisioned_yaml("prometheus.yml").fetch("scrape_configs")).to eq([])
  end

  it "uses Tempo monolithic filesystem storage and finite configurable retention without extra services" do
    tempo = provisioned_yaml("tempo.yml")
    expect(tempo.dig("distributor", "receivers", "otlp", "protocols", "http", "endpoint")).to eq("0.0.0.0:4318")
    expect(tempo.dig("storage", "trace")).to include("backend" => "local", "wal" => { "path" => "/var/tempo/wal" }, "local" => { "path" => "/var/tempo/blocks" })
    expect(tempo.dig("backend_worker", "compaction", "block_retention")).to eq("${TEMPO_RETENTION:-168h}")
    expect(tempo).not_to have_key("ingester")
    expect(tempo).not_to have_key("ingest")
  end

  it "provisions builtin Grafana data sources, trace links and SDK-compatible dashboard queries" do
    sources = provisioned_yaml("grafana/provisioning/datasources/coordinator.yml").fetch("datasources").index_by { _1.fetch("uid") }
    expect(sources.fetch("coordinator-prometheus")).to include("type" => "prometheus", "url" => "http://prometheus:9090", "isDefault" => true)
    tempo = sources.fetch("coordinator-tempo")
    expect(tempo).to include("type" => "tempo", "url" => "http://tempo:3200")
    expect(tempo.dig("jsonData", "tracesToMetrics", "datasourceUid")).to eq("coordinator-prometheus")
    expect(tempo.dig("jsonData", "tracesToMetrics", "queries").map { _1.fetch("query") }.join).to include("$$__tags")
    provider = provisioned_yaml("grafana/provisioning/dashboards/coordinator.yml").fetch("providers").sole
    expect(provider.fetch("options")).to eq("path" => "/var/lib/grafana/coordinator-dashboards")
    dashboard = JSON.parse(File.read(Rails.root.join("config/observability/grafana/dashboards/coordinator.json")))
    expect(dashboard.fetch("uid")).to eq("coordinator-observability")
    expect(dashboard.fetch("panels").map { _1.fetch("type") }.uniq).to eq([ "timeseries" ])
    expressions = dashboard.fetch("panels").flat_map { _1.fetch("targets") }.map { _1.fetch("expr") }.join
    expect(expressions).to include("coordinator_mcp_completed_total", "coordinator_subscription_duration_seconds_bucket", "coordinator_sql_duration_seconds_bucket", "coordinator_subscription_oldest_in_flight_seconds")
    expect(expressions).not_to include("correlation_id", "event_id", "task_id")
  end
end
