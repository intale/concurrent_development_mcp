# frozen_string_literal: true

parallel_test_number = Rails.env.test? ? ENV.fetch("TEST_ENV_NUMBER", "") : ""
database = if Rails.env.test?
  "eventstore#{parallel_test_number}_test"
elsif Rails.env.development?
  "eventstore_migration_target_v7"
else
  "eventstore"
end
pg_uri = ENV.fetch("PG_EVENTSTORE_URI", "postgresql://postgres:postgres@localhost:6432/#{database}")

if parallel_test_number != ""
  parsed_uri = URI.parse(pg_uri)
  parsed_uri.path = "/#{database}"
  pg_uri = parsed_uri.to_s
end

PgEventstore.configure do |config|
  config.pg_uri = pg_uri
  config.connection_pool_size = 15
  config.eventstore_role = PgEventstore::Config::NodeRole::PRIMARY
  config.middlewares = {
    event_trace: PgEventstore::Middleware::EventTracing.new
  }
end
