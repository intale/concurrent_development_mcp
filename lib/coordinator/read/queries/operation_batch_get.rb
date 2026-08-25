# frozen_string_literal: true

module Coordinator::Read
  module Queries
    class OperationBatchGet < Dry::Operation
      def initialize(contract: Contracts::OperationBatchGet.new, batches: Repositories::OperationBatches.new)
        @contract = contract
        @batches = batches
      end

      def call(input)
        validated = @contract.call(input)
        return invalid_result(validated.errors.to_h) if validated.failure?

        query = OperationBatchGetQueryV1.new(
          batch_id: validated[:batch_id],
          after_index: validated[:after_index],
          limit: validated[:limit] || Types::OPERATION_BATCH_QUERY_MAXIMUM_ITEMS
        )
        batch = @batches.fetch(query)
        return not_found_result(query.batch_id) unless batch

        QueryResultV1.new(
          status: "ok",
          summary: "Latest available projected Operation Batch progress.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::OperationBatchData.new(batch:),
          warnings: [],
          next_actions: []
        )
      end

      private

      def not_found_result(batch_id)
        QueryResultV1.new(
          status: "not_found",
          summary: "No projected Operation Batch is currently available for this ID.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "operation_batch_not_observed",
            message: "The read side has not observed this Operation Batch",
            details: { batch_id: }
          ),
          warnings: [],
          next_actions: []
        )
      end

      def invalid_result(details)
        QueryResultV1.new(
          status: "invalid",
          summary: "operation_batch_get input is invalid.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "invalid_input",
            message: "operation_batch_get input is invalid",
            details:
          ),
          warnings: [],
          next_actions: []
        )
      end
    end
  end
end
