# frozen_string_literal: true

module Coordinator
  module Subscriptions
    class CommandReceipts < Registration
      DEFINITION = ReadModelDefinition.new(
        set_name: ReadModelSet::SET_NAME,
        subscription_name: "command-receipts-v1",
        streams: [ StreamFilter.new(context: "CoordinatorControl", stream_name: "Command") ],
        event_types: [ "CommandCompleted" ]
      )

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end
