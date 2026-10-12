# frozen_string_literal: true

module Coordinator::Processes
  module Subscriptions
    class WorkIntentionSetRenewal < Coordinator::Shared::Subscriptions::Registration
      DEFINITION = ProcessDefinition.new(set_name: ProcessManagerSet::SET_NAME,
        subscription_name: "work-intention-set-renewal-v1",
        streams: [ Coordinator::Shared::Subscriptions::StreamFilter.new(context: "DevelopmentCoordination", stream_name: "WorkIntentionSetRenewal") ],
        event_types: [ "WorkIntentionSetRenewalRequested" ])

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end
