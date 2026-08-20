# frozen_string_literal: true

PgEventstore.configure do |config|
  database = Rails.env.test? ? "eventstore_test" : "eventstore"
  config.pg_uri = ENV.fetch("PG_EVENTSTORE_URI", "postgresql://postgres:postgres@localhost:6432/#{database}")
  config.connection_pool_size = 20
  config.middlewares = { event_trace: PgEventstore::Middleware::EventTracing.new }
  config.eventstore_role = PgEventstore::Config::NodeRole::PRIMARY
end
