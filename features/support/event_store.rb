# frozen_string_literal: true

require "pg_eventstore/rspec/test_helpers"
require Rails.root.join("spec/support/event_store_test_safety").to_s

Before do
  EventStoreTestSafety.verify!
  PgEventstore::TestHelpers.clean_up_db
end
