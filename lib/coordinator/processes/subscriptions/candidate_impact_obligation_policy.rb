# frozen_string_literal: true

module Coordinator::Processes
  module Subscriptions
    class CandidateImpactObligationPolicy < Coordinator::Shared::Subscriptions::Registration
      DEFINITION = ProcessDefinition.new(
        set_name: ProcessManagerSet::SET_NAME,
        subscription_name: "candidate-impact-obligation-policy-v1",
        streams: [
          Coordinator::Shared::Subscriptions::StreamFilter.new(
            context: "HumanGuidance",
            stream_name: "DecisionPartition"
          ),
          Coordinator::Shared::Subscriptions::StreamFilter.new(
            context: "DevelopmentIntegration",
            stream_name: "Candidate"
          ),
          Coordinator::Shared::Subscriptions::StreamFilter.new(
            context: "DevelopmentIntegration",
            stream_name: "CandidateImpactRegistrySweep"
          ),
          Coordinator::Shared::Subscriptions::StreamFilter.new(
            context: "DevelopmentIntegration",
            stream_name: "CandidateImpactPairScan"
          )
        ],
        event_types: %w[
          DecisionAddedToPartition
          DecisionRemovedFromPartition
          CandidateImpactSurfaceAssigned
          CandidateImpactRegistrySweepStarted
          CandidateImpactRegistrySweepProgressed
          CandidateImpactPairScanStarted
          CandidateImpactPairScanProgressed
        ]
      )

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end
