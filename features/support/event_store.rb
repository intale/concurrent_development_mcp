# frozen_string_literal: true

require "pg_eventstore/rspec/test_helpers"
require Rails.root.join("spec/support/event_store_test_safety").to_s
require Rails.root.join("spec/support/read_model_test_safety").to_s

Before do |scenario|
  stop_live_subscriptions
  ReadModelTestSafety.clean!
  EventStoreTestSafety.clean!
  reset_acceptance_repositories!
  register_acceptance_repository unless scenario.source_tag_names.include?("@history-migration")
end
