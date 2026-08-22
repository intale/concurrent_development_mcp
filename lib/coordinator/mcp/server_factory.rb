# frozen_string_literal: true

module Coordinator
  module Mcp
    class ServerFactory
      CAPABILITIES = {
        tools: { listChanged: true },
        prompts: { listChanged: true },
        resources: { listChanged: true },
        logging: {},
        extensions: Tasks::Capability::EXTENSIONS
      }.freeze

      INSTRUCTIONS = <<~TEXT.freeze
        Coordinate checkpointed concurrent development across repositories.
        Actor fields are attribution labels, not authenticated identities.
        Every application request requires the io.modelcontextprotocol/tasks capability.
        Mutations return durable Task handles: persist each taskId, poll tasks/get at
        pollIntervalMs, and use tasks/cancel for cooperative cancellation. Reuse command_id
        after an unknown mutation result. Read tools return the latest available projection,
        which may be stale; command decisions recheck authoritative event-store facts.
        The coordinator records attributed evidence and does not execute Git, CI, or agent work.
      TEXT

      def initialize(tasks_extension:)
        @tasks_extension = tasks_extension
      end

      def call
        server = Tasks::Server.new(
          name: "concurrent-development-coordinator",
          title: "Concurrent Development Coordinator",
          version: "0.1.0",
          instructions: INSTRUCTIONS,
          tools: ToolRegistry.all,
          capabilities: CAPABILITIES,
          configuration: ::MCP::Configuration.new(
            exception_reporter: method(:report_exception),
            validate_tool_call_arguments: true,
            validate_tool_call_results: true
          ),
          server_context: {}
        )
        @tasks_extension.register(server)
      end

      private

      def report_exception(error, _server_context)
        Rails.error.report(error, handled: true)
      end
    end
  end
end
