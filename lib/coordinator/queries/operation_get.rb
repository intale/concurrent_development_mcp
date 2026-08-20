# frozen_string_literal: true

module Coordinator
  module Queries
    class OperationGet < Dry::Operation
      def initialize(
        contract: Contracts::OperationGet.new,
        completion_lookup: CommandCompletionLookup.new,
        progress: CoordContextProgress.new
      )
        @contract = contract
        @completion_lookup = completion_lookup
        @progress = progress
      end

      def call(input)
        validated = @contract.call(input)
        return invalid_result(validated.errors.to_h) if validated.failure?

        query = OperationGetQueryV1.new(
          command_id: validated[:command_id],
          projections: validated[:projections] || [ "coord_context_v1" ]
        )
        completion = @completion_lookup.fetch(query.command_id)
        return not_found_result(query.command_id) unless completion

        projection_progress = selected_progress(query, completion)
        pending = projection_progress.any? { !_1.complete }
        completion_result(completion, projection_progress:, pending:)
      end

      private

      def selected_progress(query, completion)
        query.projections.filter_map do |projection_name|
          @progress.call(completion) if projection_name == "coord_context_v1"
        end.freeze
      end

      def completion_result(completion, projection_progress:, pending:)
        McpResultV1.new(
          status: pending ? "pending_projection" : "ok",
          summary: pending ? "The command committed, but its context projection is not current yet." : completion.summary,
          command_id: completion.command_id,
          receipt: completion.receipt,
          context_token: completion.context_token,
          data: McpResultV1::OperationData.new(
            result: completion.data,
            emitted_events: completion.emitted_events,
            projection_barriers: completion.projection_barriers,
            projection_progress:
          ),
          warnings: completion.warnings,
          next_actions: pending ? [ operation_refresh(completion.command_id) ] : completion.next_actions,
          projection_status: pending ? "pending" : "current_for_requested_command"
        )
      end

      def not_found_result(command_id)
        McpResultV1.new(
          status: "not_found",
          summary: "No completed command exists for the supplied command ID.",
          command_id:,
          receipt: nil,
          context_token: nil,
          data: McpResultV1::EmptyData.new({}),
          warnings: [],
          next_actions: [],
          projection_status: nil
        )
      end

      def invalid_result(details)
        McpResultV1.new(
          status: "invalid",
          summary: "operation_get input is invalid.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: McpResultV1::DomainError.new(
            code: "invalid_input",
            message: "operation_get input is invalid",
            details:
          ),
          warnings: [],
          next_actions: [],
          projection_status: nil
        )
      end

      def operation_refresh(command_id)
        NextAction.new(
          tool: "operation_get",
          arguments: NextAction::OperationArguments.new(command_id:)
        )
      end
    end
  end
end
