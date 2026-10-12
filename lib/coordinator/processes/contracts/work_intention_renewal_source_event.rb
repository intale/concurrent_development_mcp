# frozen_string_literal: true

module Coordinator::Processes
  module Contracts
    class WorkIntentionRenewalSourceEvent < Dry::Validation::Contract
      params do
        required(:event).value(Coordinator::Shared::Types.Instance(PgEventstore::Event))
      end

      rule(:event) do
        event = value
        valid = event.type == "WorkIntentionSetRenewalRequested" && event.metadata["schema_version"] == 1 &&
          event.stream.context == "DevelopmentCoordination" && event.stream.stream_name == "WorkIntentionSetRenewal" &&
          event.stream.stream_id == event.metadata["command_id"] && event.stream_revision == 0 &&
          event.metadata["actor_kind"] == "agent" && event.correlation_id && event.causation_id
        key.failure("must be a correlated, attributed renewal request in its own stream") unless valid
      end
    end
  end
end
