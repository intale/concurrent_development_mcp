# frozen_string_literal: true

parallel_test_number = Rails.env.test? ? ENV.fetch("TEST_ENV_NUMBER", "") : ""
database = if Rails.env.test?
  "eventstore#{parallel_test_number}_test"
else
  "eventstore_migration_target_v7"
end
pg_uri = ENV.fetch("PG_EVENTSTORE_URI") do
  if Rails.env.production?
    username = URI.encode_uri_component(ENV.fetch("DATABASE_USERNAME"))
    password = URI.encode_uri_component(ENV.fetch("DATABASE_PASSWORD"))
    URI::Generic.build(
      scheme: "postgresql",
      userinfo: "#{username}:#{password}",
      host: ENV.fetch("DATABASE_HOST"),
      port: Integer(ENV.fetch("DATABASE_PORT", "5432")),
      path: "/#{ENV.fetch("PG_EVENTSTORE_DATABASE_NAME", "eventstore_production") }"
    ).to_s
  else
    "postgresql://postgres:postgres@localhost:6432/#{database}"
  end
end

if parallel_test_number != ""
  parsed_uri = URI.parse(pg_uri)
  parsed_uri.path = "/#{database}"
  pg_uri = parsed_uri.to_s
end

PgEventstore.configure do |config|
  config.pg_uri = pg_uri
  config.connection_pool_size = Integer(ENV.fetch("PG_EVENTSTORE_POOL", "15"))
  config.eventstore_role = PgEventstore::Config::NodeRole::PRIMARY
  config.middlewares = {
    event_trace: PgEventstore::Middleware::EventTracing.new
  }
end
