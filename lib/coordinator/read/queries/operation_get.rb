# frozen_string_literal: true

module Coordinator::Read
  module Queries
    class OperationGet < Dry::Operation
      def initialize(
        contract: Contracts::OperationGet.new,
        results: CommandResultLookup.new
      )
        @contract = contract
        @results = results
      end

      def call(input)
        validated = @contract.call(input)
        return invalid_result(validated.errors.to_h) if validated.failure?

        query = OperationGetQueryV1.new(command_id: validated[:command_id])
        result = @results.fetch(query.command_id)
        return not_found_result(query.command_id) unless result
        return rejected_result(result) unless result.status == "ok"

        QueryResultV1.new(
          status: "ok",
          summary: result.summary,
          command_id: result.command_id,
          receipt: result.receipt,
          context_token: nil,
          data: QueryResultV1::OperationData.new(
            result: result.data,
            emitted_events: result.emitted_events
          ),
          warnings: result.warnings,
          next_actions: result.next_actions
        )
      end

      private

      def rejected_result(result)
        error = Coordinator::Write::Tasks::DomainErrorV1::Type[result.data]
        QueryResultV1.new(
          status: result.status,
          summary: result.summary,
          command_id: result.command_id,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: error.code,
            message: error.message,
            details: error.details.to_h
          ),
          warnings: result.warnings,
          next_actions: result.next_actions
        )
      end

      def not_found_result(command_id)
        QueryResultV1.new(
          status: "not_found",
          summary: "No projected command receipt exists for the supplied command ID.",
          command_id:,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::EmptyData.new({}),
          warnings: [],
          next_actions: []
        )
      end

      def invalid_result(details)
        QueryResultV1.new(
          status: "invalid",
          summary: "operation_get input is invalid.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "invalid_input",
            message: "operation_get input is invalid",
            details:
          ),
          warnings: [],
          next_actions: []
        )
      end
    end
  end
end
