# frozen_string_literal: true

module Coordinator::Processes
  module Subscriptions
    class ChangeSetReadiness < Coordinator::Shared::Subscriptions::Registration
      DEFINITION = Coordinator::Shared::Subscriptions::Definition.new(
        set_name: ProcessManagerSet::SET_NAME,
        subscription_name: "change-set-readiness-v1",
        stream_context: "DevelopmentPlanning",
        stream_name: "ChangeSet",
        event_type: "ChangeSetActivated"
      )

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end
