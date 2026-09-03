# frozen_string_literal: true

module Coordinator::Read
  module Subscriptions
    class CommandReceipts < Coordinator::Shared::Subscriptions::Registration
      DEFINITION = ReadModelDefinition.new(
        set_name: TaskResultSet::SET_NAME,
        subscription_name: "command-receipts-v2",
        streams: [ Coordinator::Shared::Subscriptions::StreamFilter.new(context: "CoordinatorControl", stream_name: "Command") ],
        event_types: [ "CommandSucceeded", "CommandRejected" ]
      )

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end
