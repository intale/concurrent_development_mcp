# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class OperationBatchSourceEvent < Dry::Validation::Contract
      params do
        required(:event_type).filled(:string, included_in?: %w[
          OperationBatchCreated
          OperationBatchItemSucceeded
          OperationBatchItemRejected
          OperationBatchContinuationRequested
          OperationBatchCancellationRequested
          OperationBatchCancelled
          OperationBatchCompleted
        ])
        required(:schema_version).filled(:integer, eql?: 2)
        required(:stream_context).filled(:string, eql?: "DevelopmentCoordination")
        required(:stream_name).filled(:string, eql?: "OperationBatch")
        required(:stream_id).filled(:string)
        required(:stream_revision).filled(:integer)
        required(:global_position).filled(:integer)
        required(:command_id).filled(:string)
        required(:actor_kind).filled(:string)
        required(:actor_id).filled(:string)
        required(:recorded_by).filled(:string, eql?: "coordinator")
        required(:policy_version).filled(:string, eql?: "operation-batch/v2")
      end
    end
  end
end
