# frozen_string_literal: true

RSpec.describe "production Compose configuration" do
  def compose_configuration(overrides = {})
    environment = {
      "POSTGRES_PASSWORD" => "compose-configuration-spec", "SECRET_KEY_BASE" => "compose-configuration-spec",
      "POSTGRES_USER" => nil, "PG_HOST_DATA_DIR" => nil,
      "POSTGRES_HOST_PORT" => nil, "PGBOUNCER_HOST_PORT" => nil
    }.merge(overrides)
    output, error, status = Open3.capture3(
      environment, "docker", "compose", "--env-file", "/dev/null",
      "-f", Rails.root.join("docker-compose.production.yml").to_s,
      "config", "--format", "json"
    )
    [ status, output, error ]
  end

  it "publishes database ports only on loopback and preserves PostgreSQL 18 host data" do
    status, output, error = compose_configuration
    expect(status).to be_success, error
    services = JSON.parse(output).fetch("services")
    expect(services.dig("postgres", "ports")).to include(include("host_ip" => "127.0.0.1", "published" => "6435"))
    expect(services.dig("pgbouncer", "ports")).to include(include("host_ip" => "127.0.0.1", "published" => "6436"))
    expect(services.dig("postgres", "volumes")).to include(
      include("type" => "bind", "source" => Rails.root.join("data").to_s, "target" => "/var/lib/postgresql")
    )
    expect(services.dig("postgres", "environment", "PGDATA")).to eq("/var/lib/postgresql/18/docker")
  end

  it "allows an explicitly selected external data directory" do
    status, output, error = compose_configuration("PG_HOST_DATA_DIR" => "/srv/coordinator-postgres")
    expect(status).to be_success, error
    volume = JSON.parse(output).dig("services", "postgres", "volumes").first
    expect(volume).to include("type" => "bind", "source" => "/srv/coordinator-postgres")
  end

  it "routes preparation through healthy transaction pooling without an automatic restart" do
    status, output, error = compose_configuration
    expect(status).to be_success, error
    services = JSON.parse(output).fetch("services")
    expect(services.dig("pgbouncer", "environment")).to include("POOL_MODE" => "transaction", "AUTH_TYPE" => "scram-sha-256")
    expect(services.dig("pgbouncer", "environment")).not_to have_key("DB_NAME")
    expect(services.dig("prepare", "environment")).to include("RAILS_ENV" => "production", "DATABASE_HOST" => "pgbouncer", "DATABASE_PORT" => "5432")
    expect(services.dig("prepare", "depends_on", "pgbouncer", "condition")).to eq("service_healthy")
    expect(services.dig("prepare", "restart")).to eq("no")
    expect(services.dig("prepare", "command")).to eq([ "./bin/prepare-production" ])
  end

  %w[POSTGRES_PASSWORD SECRET_KEY_BASE].each do |variable|
    it "rejects deployment configuration without #{variable}" do
      status, _, error = compose_configuration(variable => nil)
      expect(status).not_to be_success
      expect(error).to include(variable)
    end
  end

  it "rejects unsafe database identifiers before starting preparation" do
    environment = {
      "RAILS_ENV" => "production", "DATABASE_NAME" => "invalid-database-name"
    }
    _, error, status = Open3.capture3(environment, Rails.root.join("bin/prepare-production").to_s)
    expect(status.exitstatus).to eq(64)
    expect(error).to include("DATABASE_NAME must be a lowercase SQL identifier")
  end

  it "rejects duplicate database roles before starting preparation" do
    environment = {
      "RAILS_ENV" => "production", "DATABASE_USERNAME" => "coordinator",
      "DATABASE_NAME" => "same_database", "CACHE_DATABASE_NAME" => "same_database",
      "QUEUE_DATABASE_NAME" => "queue_database", "PG_EVENTSTORE_DATABASE_NAME" => "eventstore_database"
    }
    _, error, status = Open3.capture3(environment, Rails.root.join("bin/prepare-production").to_s)
    expect(status.exitstatus).to eq(64)
    expect(error).to include("four distinct names")
  end
end
