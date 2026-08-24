# frozen_string_literal: true

PgEventstore.configure do |config|
  parallel_test_number = Rails.env.test? ? ENV.fetch("TEST_ENV_NUMBER", "") : ""
  database = Rails.env.test? ? "eventstore#{parallel_test_number}_test" : "eventstore"
  pg_uri = ENV.fetch("PG_EVENTSTORE_URI", "postgresql://postgres:postgres@localhost:6432/#{database}")

  if parallel_test_number != ""
    parsed_uri = URI.parse(pg_uri)
    parsed_uri.path = "/#{database}"
    pg_uri = parsed_uri.to_s
  end

  config.pg_uri = pg_uri
  config.connection_pool_size = 15
  config.eventstore_role = PgEventstore::Config::NodeRole::PRIMARY
  config.middlewares = {
    event_trace: PgEventstore::Middleware::EventTracing.new
  }
end
