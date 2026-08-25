# frozen_string_literal: true

module Coordinator::Processes
  module Subscriptions
    class OperationBatchRunner < Coordinator::Shared::Subscriptions::Registration
      DEFINITION = ProcessDefinition.new(
        set_name: ProcessManagerSet::SET_NAME,
        subscription_name: "operation-batch-runner-v1",
        streams: [
          Coordinator::Shared::Subscriptions::StreamFilter.new(
            context: "DevelopmentCoordination",
            stream_name: "OperationBatch"
          )
        ],
        event_types: %w[
          OperationBatchCreated
          OperationBatchContinuationRequested
          OperationBatchCancellationRequested
        ]
      )

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end
