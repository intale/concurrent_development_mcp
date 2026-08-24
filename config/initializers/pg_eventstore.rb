# frozen_string_literal: true

PgEventstore.configure do |config|
  database = Rails.env.test? ? "eventstore_test" : "eventstore"
  config.pg_uri = ENV.fetch("PG_EVENTSTORE_URI", "postgresql://postgres:postgres@localhost:6432/#{database}")
  config.connection_pool_size = 20
  config.eventstore_role = PgEventstore::Config::NodeRole::PRIMARY
end

Rails.application.config.to_prepare do
  PgEventstore.configure do |config|
    config.middlewares = {
      event_trace: Coordinator::Write::Middlewares::RootCorrelationEventTracing.new
    }
  end
end
