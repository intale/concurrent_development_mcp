# frozen_string_literal: true

abort("Projection number replay must be explicitly approved before a production run") if Rails.env.production?

ENV["COORDINATOR_OBSERVABILITY_ROLE"] = "subscriptions"
Coordinator::Read::Subscriptions::ProjectionNumbersReplaySet.new(
  artifact_handler: Coordinator::Container["projectors.development_artifacts_v1"],
  checkpoint_handler: Coordinator::Container["projectors.coord_context_v1"]
).start
