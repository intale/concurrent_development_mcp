# frozen_string_literal: true

module Coordinator::Read
  module Subscriptions
    class OperationBatches < BatchRegistration
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
          OperationBatchTargetSelected
          OperationBatchManifestAccepted
          OperationBatchSucceededItemsNumberChanged
          OperationBatchUnsuccessfulItemsNumberChanged
          OperationBatchOutcomeRecorded
          OperationBatchItemEnqueued
          OperationBatchItemCommandAssigned
          OperationBatchItemExecutionStarted
          OperationBatchItemRegistrationRejected
          OperationBatchItemSucceeded
          OperationBatchItemRejected
          OperationBatchItemFailed
          OperationBatchItemCompletionLinked
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
