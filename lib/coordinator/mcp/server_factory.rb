# frozen_string_literal: true

module Coordinator
  module Mcp
    class ServerFactory
      INSTRUCTIONS = <<~TEXT.freeze
        Coordinate checkpointed concurrent development across repositories.
        Actor fields are attribution labels, not authenticated identities.
        Reuse command_id after an unknown mutation result. Use operation_get and
        coord_context to inspect exact projection freshness; do not infer completion.
        The coordinator records attributed evidence and does not execute Git, CI, or agent work.
      TEXT

      def call
        ::MCP::Server.new(
          name: "concurrent-development-coordinator",
          title: "Concurrent Development Coordinator",
          version: "0.1.0",
          instructions: INSTRUCTIONS,
          tools: ToolRegistry.all,
          configuration: ::MCP::Configuration.new(
            exception_reporter: method(:report_exception),
            validate_tool_call_arguments: true,
            validate_tool_call_results: true
          ),
          server_context: {}
        )
      end

      private

      def report_exception(error, _server_context)
        Rails.error.report(error, handled: true)
      end
    end
  end
end
