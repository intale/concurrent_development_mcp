# frozen_string_literal: true

module Coordinator
  module Subscriptions
    class ChangeSetReadiness < Registration
      DEFINITION = Definition.new(
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
