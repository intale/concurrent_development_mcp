# frozen_string_literal: true

abort("Projection initialization must be explicitly approved before a production run") if Rails.env.production?

ENV["COORDINATOR_OBSERVABILITY_ROLE"] = "projection-initialization"
Coordinator::Processes::Subscriptions::ProjectionInitializationSet.new(
  event_store: Coordinator::Container["event_store"]
).start
