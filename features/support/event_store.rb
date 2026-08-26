# frozen_string_literal: true

require "pg_eventstore/rspec/test_helpers"
require Rails.root.join("spec/support/event_store_test_safety").to_s
require Rails.root.join("spec/support/read_model_test_safety").to_s

Before do
  ReadModelTestSafety.clean!
  EventStoreTestSafety.verify!
  PgEventstore::TestHelpers.clean_up_db
  reset_acceptance_repositories!
  register_acceptance_repository
end
