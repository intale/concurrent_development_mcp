# frozen_string_literal: true

module EventStoreTestSafety
  module_function

  def verify!
    database = URI.parse(PgEventstore.config.pg_uri).path.delete_prefix("/")
    return if Rails.env.test? && database.end_with?("_test")

    raise "Refusing to clean a non-test pg_eventstore database: #{database.inspect}"
  end
end
