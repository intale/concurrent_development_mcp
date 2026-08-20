# frozen_string_literal: true

module ReadModelTestSafety
  module_function

  def verify!
    database = ActiveRecord::Base.connection_db_config.database
    return if Rails.env.test? && database.end_with?("_test")

    raise "Refusing to clean a non-test read-model database: #{database.inspect}"
  end

  def clean!
    verify!
    Coordinator::ReadModels::ProcessedProjectionEvent.delete_all
    Coordinator::ReadModels::CommandReceipt.delete_all
    Coordinator::ReadModels::CoordContextScope.delete_all
    Coordinator::ReadModels::CoordContext.delete_all
  end
end
