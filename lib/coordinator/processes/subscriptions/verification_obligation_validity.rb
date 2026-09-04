# frozen_string_literal: true

module Coordinator::Processes
  module Subscriptions
    class VerificationObligationValidity < Coordinator::Shared::Subscriptions::Registration
      DEFINITION = ProcessDefinition.new(
        set_name: ProcessManagerSet::SET_NAME,
        subscription_name: "verification-obligation-validity-v1",
        streams: [
          Coordinator::Shared::Subscriptions::StreamFilter.new(
            context: "HumanGuidance",
            stream_name: "DecisionPartition"
          ),
          Coordinator::Shared::Subscriptions::StreamFilter.new(
            context: "DevelopmentIntegration",
            stream_name: "VerificationObligation"
          ),
          Coordinator::Shared::Subscriptions::StreamFilter.new(
            context: "DevelopmentIntegration",
            stream_name: "VerificationObligationValidityScan"
          )
        ],
        event_types: %w[
          DecisionPartitionAdvanced
          DecisionAddedToPartition
          DecisionRemovedFromPartition
          VerificationObligationCreated
          VerificationObligationValidityScanStarted
          VerificationObligationValidityScanProgressed
        ]
      )

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end
