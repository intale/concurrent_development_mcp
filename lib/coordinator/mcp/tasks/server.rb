# frozen_string_literal: true

module Coordinator::Mcp
  module Tasks
    class Server < ::MCP::Server
      def initialize(observability:, **options)
        @observability = observability
        super(**options)
      end

      # The SDK's public Hash and JSON entrypoints are independent. Wrapping
      # each here covers both transports without a second tool-level span.
      def handle(request, session: nil)
        @observability.call(request) { super }
      end

      def handle_json(request, session: nil)
        @observability.call(request) { super }
      end

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
