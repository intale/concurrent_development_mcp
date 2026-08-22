# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    class ToolResultMapper
      STATUS_BY_CODE = {
        command_id_reused: "command_id_reused",
        work_item_unavailable: "conflict",
        attempt_already_exists: "conflict",
        lease_busy: "busy",
        interpretation_slot_already_accepted: "conflict"
      }.freeze

      def call(result, command_id:)
        structured_content = if result.success?
                               success_content(result.value!)
        else
                               failure_content(result.failure, command_id:)
        end

        ToolResultV1.new(
          content: [
            TextContentV1.new(
              type: "text",
              text: JSON.generate(structured_content.to_h)
            )
          ],
          is_error: result.failure?,
          structured_content:
        )
      end

      private

      def success_content(completion)
        StructuredContentV1.new(
          status: "ok",
          summary: completion.summary,
          command_id: completion.command_id,
          receipt: completion.receipt,
          context_token: nil,
          data: completion.data,
          warnings: completion.warnings,
          next_actions: completion.next_actions
        )
      end

      def failure_content(error, command_id:)
        domain_error = DomainErrorV1::Type[
          {
            code: error.code.to_s,
            message: error.message,
            details: error.details
          }
        ]

        StructuredContentV1.new(
          status: STATUS_BY_CODE.fetch(error.code, "denied"),
          summary: error.message,
          command_id:,
          receipt: nil,
          context_token: nil,
          data: domain_error,
          warnings: [],
          next_actions: []
        )
      end
    end
  end
end
