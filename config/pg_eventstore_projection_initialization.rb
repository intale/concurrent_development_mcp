# frozen_string_literal: true

if Rails.env.production? && ENV["COORDINATOR_ALLOW_PROJECTION_MIGRATION"] != "1"
  abort("Use bin/migrate-production for an explicitly approved production initialization")
end

ENV["COORDINATOR_OBSERVABILITY_ROLE"] = "subscriptions"
Coordinator::Processes::Subscriptions::ProjectionInitializationSet.new(
  event_store: Coordinator::Container["event_store"]
).start
