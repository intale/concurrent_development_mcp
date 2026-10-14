# frozen_string_literal: true

if Rails.env.production? && ENV["COORDINATOR_ALLOW_PROJECTION_MIGRATION"] != "1"
  abort("Use bin/migrate-production for an explicitly approved production count replay")
end

ENV["COORDINATOR_OBSERVABILITY_ROLE"] = "subscriptions"
Coordinator::Read::Subscriptions::ProjectionNumbersReplaySet.new(
  artifact_handler: Coordinator::Container["projectors.development_artifacts_v1"],
  checkpoint_handler: Coordinator::Container["projectors.coord_context_v1"]
).start
