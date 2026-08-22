# frozen_string_literal: true

module Coordinator
  module Mcp
    class ResultMapper
      STATUS_BY_CODE = {
        invalid_input: "invalid",
        invalid_git_oid: "invalid",
        command_id_reused: "command_id_reused",
        work_item_unavailable: "conflict",
        duplicate_change_set_id: "conflict",
        duplicate_work_item_id: "conflict",
        duplicate_dependency_id: "conflict",
        attempt_already_exists: "conflict"
      }.freeze

      def call(result, command_id: nil)
        return success_result(result.value!) if result.success?

        failure_result(result.failure, command_id:)
      end

      private

      def success_result(value)
        return query_result(value) if value.is_a?(Coordinator::Read::QueryResultV1)

        ResultV1.new(
          status: "ok",
          summary: value.summary,
          command_id: value.command_id,
          receipt: value.receipt,
          context_token: nil,
          data: value.data,
          warnings: value.warnings,
          next_actions: value.next_actions
        )
      end

      def query_result(value)
        ResultV1.new(value.to_h)
      end

      def failure_result(error, command_id:)
        ResultV1.new(
          status: STATUS_BY_CODE.fetch(error.code, "denied"),
          summary: error.message,
          command_id:,
          receipt: nil,
          context_token: nil,
          data: ResultV1::DomainError.new(
            code: error.code.to_s,
            message: error.message,
            details: error.details
          ),
          warnings: [],
          next_actions: []
        )
      end
    end
  end
end
