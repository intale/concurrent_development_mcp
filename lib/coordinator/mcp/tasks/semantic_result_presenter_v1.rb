# frozen_string_literal: true

module Coordinator::Mcp
  module Tasks
    class SemanticResultPresenterV1
      def call(result)
        structured_content, is_error =
          case result
          when Coordinator::Write::Tasks::SemanticResultV1::Success
            [ success_content(result), false ]
          when Coordinator::Write::Tasks::SemanticResultV1::DomainRejection
            [ rejection_content(result), true ]
          end

        ResultV1::CallToolResult.new(
          content: [
            Coordinator::Write::Tasks::TextContentV1.new(
              type: "text",
              text: JSON.generate(structured_content.to_h)
            )
          ],
          isError: is_error,
          structuredContent: structured_content
        )
      end

      private

      def success_content(result)
        Coordinator::Write::Tasks::StructuredContentV1.new(
          status: "ok",
          summary: result.summary,
          command_id: result.command_id,
          receipt: result.receipt,
          context_token: nil,
          data: result.data,
          warnings: result.warnings,
          next_actions: result.next_actions
        )
      end

      def rejection_content(result)
        Coordinator::Write::Tasks::StructuredContentV1.new(
          status: result.status,
          summary: result.summary,
          command_id: result.command_id,
          receipt: nil,
          context_token: nil,
          data: result.error,
          warnings: [],
          next_actions: result.next_actions
        )
      end
    end
  end
end
