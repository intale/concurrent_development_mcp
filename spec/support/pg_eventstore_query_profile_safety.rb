# frozen_string_literal: true

# A manual performance diagnostic must never attach to development or production
# data, or to one of the ordinary parallel test runners' databases.
module PgEventstoreQueryProfileSafety
  module_function

  def verify!
    suffix = ENV.fetch("TEST_ENV_NUMBER")
    unless Rails.env.test? && /\Apgq_[a-z0-9_]+\z/.match?(suffix)
      raise "Query profiling requires a dedicated pgq_* test database suffix"
    end

    expected = "eventstore#{suffix}_test"
    PgEventstore.available_configs.each do |name|
      uri = URI.parse(PgEventstore.config(name).pg_uri)
      unless [ "localhost", "127.0.0.1" ].include?(uri.host) && uri.path == "/#{expected}"
        raise "Refusing to profile a non-isolated event store: #{name}"
      end
    end
    unless ActiveRecord::Base.connection_db_config.database == "concurrent_development_mcp#{suffix}_test"
      raise "Refusing to profile a non-isolated Rails database"
    end

    output = File.expand_path(ENV.fetch("PG_QUERY_PROFILE_DIR"))
    unless output.start_with?(Rails.root.join("tmp", "pg_query_profile").to_s + "/")
      raise "Query profile output must be inside tmp/pg_query_profile/<run>"
    end
  end
end
