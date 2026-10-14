# frozen_string_literal: true

module Coordinator::Processes::Subscriptions
  class CheckpointStatistics < Coordinator::Shared::Subscriptions::Registration
    DEFINITION = Coordinator::Shared::Subscriptions::Definition.new(
      set_name: ProcessManagerSet::SET_NAME, subscription_name: "checkpoint-statistics-v1",
      stream_context: "DevelopmentIntegration", stream_name: "Candidate", event_types: [ "CandidateSubmitted" ])

    def initialize(handler:, pull_interval: 1.0)
      super(definition: DEFINITION, handler:, pull_interval:)
    end
  end
end
