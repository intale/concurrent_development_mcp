# frozen_string_literal: true

module EventStoreTestSafety
  module_function

  def verify!
    PgEventstore.available_configs.each do |config_name|
      database = URI.parse(PgEventstore.config(config_name).pg_uri).path.delete_prefix("/")
      next if Rails.env.test? && database.end_with?("_test")

      raise "Refusing to clean a non-test pg_eventstore database: #{database.inspect}"
    end
  end

  def clean!
    verify!
    PgEventstore.available_configs.each { PgEventstore::TestHelpers.clean_up_db(_1) }
  end
end
