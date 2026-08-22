# frozen_string_literal: true

module Coordinator::Processes
  module Subscriptions
    class LeaseExpiryScheduler < Coordinator::Shared::Subscriptions::Registration
      DEFINITION = Coordinator::Shared::Subscriptions::Definition.new(
        set_name: ProcessManagerSet::SET_NAME,
        subscription_name: "lease-expiry-scheduler-v1",
        stream_context: "DevelopmentCoordination",
        stream_name: "ResourceLease",
        event_types: [ "ResourceLeaseAcquired", "ResourceLeaseRenewed" ]
      )

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end
