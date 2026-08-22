# frozen_string_literal: true

module Coordinator::Mcp
  module Tasks
    class Server < ::MCP::Server
      private

      def call_tool(
        request,
        session: nil,
        related_request_id: nil,
        cancellation: nil,
        envelope: nil
      )
        Capability.require!(
          envelope&.client_capabilities,
          modern: !envelope.nil?,
          request:
        )

        super
      end

      def validate_tool_call_result!(tool, result)
        return if result[:resultType] == "task"

        super
      end
    end
  end
end
