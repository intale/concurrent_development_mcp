# frozen_string_literal: true

module Coordinator::Read
  module Queries
    class OperationGet < Dry::Operation
      def initialize(
        contract: Contracts::OperationGet.new,
        completions: CommandCompletionLookup.new
      )
        @contract = contract
        @completions = completions
      end

      def call(input)
        validated = @contract.call(input)
        return invalid_result(validated.errors.to_h) if validated.failure?

        query = OperationGetQueryV1.new(command_id: validated[:command_id])
        completion = @completions.fetch(query.command_id)
        return not_found_result(query.command_id) unless completion

        QueryResultV1.new(
          status: "ok",
          summary: completion.summary,
          command_id: completion.command_id,
          receipt: completion.receipt,
          context_token: nil,
          data: QueryResultV1::OperationData.new(
            result: completion.data,
            emitted_events: completion.emitted_events
          ),
          warnings: completion.warnings,
          next_actions: completion.next_actions
        )
      end

      private

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
