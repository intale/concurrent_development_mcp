# frozen_string_literal: true

module Coordinator::Processes
  module Subscriptions
    class ResourceBoundaryMaintenance < Coordinator::Shared::Subscriptions::Registration
      DEFINITION = Coordinator::Shared::Subscriptions::Definition.new(
        set_name: ProcessManagerSet::SET_NAME,
        subscription_name: "resource-boundary-maintenance-v1",
        stream_context: "DevelopmentCoordination",
        stream_name: "ResourceLease",
        event_types: Coordinator::Write::EventQueries::RESOURCE_LEASE_LIFECYCLE_EVENT_TYPES
      )

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end
