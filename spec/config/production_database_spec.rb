# frozen_string_literal: true

RSpec.describe "production database configuration" do
  def database_configuration(overrides = {})
    environment = {
      "RAILS_ENV" => "production",
      "DATABASE_HOST" => "pgbouncer",
      "DATABASE_PORT" => "5432",
      "DATABASE_USERNAME" => "coordinator",
      "DATABASE_PASSWORD" => 'password: with "quotes" # and @',
      "DATABASE_NAME" => nil,
      "CACHE_DATABASE_NAME" => nil,
      "QUEUE_DATABASE_NAME" => nil,
      "DATABASE_POOL" => nil,
      "RAILS_MAX_THREADS" => nil
    }.merge(overrides)
    script = <<~RUBY
      source = ERB.new(File.read("config/database.yml")).result
      puts JSON.generate(YAML.safe_load(source, aliases: true))
    RUBY
    output, error, status = Open3.capture3(environment, RbConfig.ruby, "-rerb", "-ryaml", "-rjson", "-e", script, chdir: Rails.root)
    [ status, output, error ]
  end

  it "keeps the three Rails databases separate and compatible with transaction pooling" do
    status, output, error = database_configuration
    expect(status).to be_success, error
    configuration = JSON.parse(output).fetch("production")

    expect(configuration.keys).to eq(%w[primary cache queue])
    expect(configuration.transform_values { _1.fetch("database") }).to eq(
      "primary" => "concurrent_development_mcp_production",
      "cache" => "concurrent_development_mcp_production_cache",
      "queue" => "concurrent_development_mcp_production_queue"
    )
    configuration.each_value do |database|
      expect(database).to include(
        "host" => "pgbouncer", "port" => 5432,
        "username" => "coordinator", "password" => 'password: with "quotes" # and @',
        "prepared_statements" => false, "advisory_locks" => false
      )
    end
    expect(configuration.fetch("cache")).to include("schema_format" => "ruby", "migrations_paths" => "db/cache_migrate")
    expect(configuration.fetch("queue")).to include("schema_format" => "ruby", "migrations_paths" => "db/queue_migrate")
  end

  it "accepts explicit database names and per-process pool sizes" do
    status, output, error = database_configuration(
      "DATABASE_NAME" => "isolated_mcp", "CACHE_DATABASE_NAME" => "isolated_cache",
      "QUEUE_DATABASE_NAME" => "isolated_queue", "DATABASE_POOL" => "12"
    )
    expect(status).to be_success, error
    configuration = JSON.parse(output).fetch("production")
    expect(configuration.values.map { _1.fetch("database") }).to eq(%w[isolated_mcp isolated_cache isolated_queue])
    expect(configuration.values.map { _1.fetch("max_connections") }).to eq([ 12, 12, 12 ])
  end

  %w[DATABASE_HOST DATABASE_USERNAME DATABASE_PASSWORD].each do |name|
    it "requires #{name} rather than silently connecting with development defaults" do
      status, _, error = database_configuration(name => nil)
      expect(status).not_to be_success
      expect(error).to include(name)
    end
  end

  it "preserves the isolated test configuration without production credentials" do
    status, output, error = database_configuration(
      "RAILS_ENV" => "test", "DATABASE_HOST" => nil,
      "DATABASE_USERNAME" => nil, "DATABASE_PASSWORD" => nil
    )
    expect(status).to be_success, error
    test = JSON.parse(output).fetch("test")
    expect(test).to include("port" => 5532, "host" => "localhost", "username" => "postgres")
    expect(test.fetch("database")).to end_with("_test")
  end

  it "boots production before its databases exist and builds an escaped pooled event-store URI" do
    environment = {
      "RAILS_ENV" => "production",
      "SECRET_KEY_BASE" => "production-configuration-spec-not-a-deployment-secret",
      "DATABASE_HOST" => "127.0.0.1", "DATABASE_PORT" => "6432",
      "DATABASE_USERNAME" => "coordinator", "DATABASE_PASSWORD" => "p a@ss:/#%",
      "PG_EVENTSTORE_URI" => nil, "PG_EVENTSTORE_DATABASE_NAME" => "production_boot_configuration_spec",
      "PG_EVENTSTORE_POOL" => "7", "RUBYOPT" => nil
    }
    script = <<~RUBY
      uri = URI.parse(PgEventstore.config.pg_uri)
      abort "incorrect URI credentials" unless URI.decode_uri_component(uri.password) == "p a@ss:/#%"
      abort "incorrect event-store address" unless uri.host == "127.0.0.1" && uri.port == 6432
      abort "incorrect database" unless uri.path == "/production_boot_configuration_spec"
      abort "incorrect pool" unless PgEventstore.config.connection_pool_size == 7
      abort "unused Cable database" unless ActiveRecord::Base.configurations.configs_for(env_name: "production").map(&:name) == %w[primary cache queue]
      puts "Production configuration boot passed"
    RUBY
    output, error, status = Open3.capture3(environment, RbConfig.ruby, "bin/rails", "runner", script, chdir: Rails.root)
    expect(status).to be_success, error
    expect(output).to include("Production configuration boot passed")
  end
end
