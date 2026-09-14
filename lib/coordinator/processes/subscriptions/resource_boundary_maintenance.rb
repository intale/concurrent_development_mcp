# frozen_string_literal: true

module Coordinator::Processes
  module Subscriptions
    class ResourceBoundaryMaintenance < Coordinator::Shared::Subscriptions::Registration
      DEFINITION = Coordinator::Shared::Subscriptions::Definition.new(
        set_name: ProcessManagerSet::SET_NAME,
        subscription_name: "resource-boundary-maintenance-v2",
        stream_context: "DevelopmentCoordination",
        stream_name: "ResourceWorkIntention",
        event_types: Coordinator::Write::EventQueries::WORK_INTENTION_LIFECYCLE_EVENT_TYPES
      )

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end
