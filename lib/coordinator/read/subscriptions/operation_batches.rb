# frozen_string_literal: true

module Coordinator::Read
  module Subscriptions
    class OperationBatches < Coordinator::Shared::Subscriptions::Registration
      DEFINITION = ReadModelDefinition.new(
        set_name: ReadModelSet::SET_NAME,
        subscription_name: "operation-batches-v2",
        streams: [
          Coordinator::Shared::Subscriptions::StreamFilter.new(
            context: "DevelopmentCoordination",
            stream_name: "OperationBatch"
          )
        ],
        event_types: %w[
          OperationBatchCreated
          OperationBatchItemSucceeded
          OperationBatchItemRejected
          OperationBatchContinuationRequested
          OperationBatchCancellationRequested
          OperationBatchCancelled
          OperationBatchCompleted
        ]
      )

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end
