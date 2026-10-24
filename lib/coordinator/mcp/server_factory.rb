# frozen_string_literal: true

module Coordinator
  module Mcp
    class ServerFactory
      CAPABILITIES = {
        tools: { listChanged: true },
        prompts: { listChanged: true },
        resources: { listChanged: true },
        logging: {},
        extensions: Tasks::Extension::CAPABILITIES
      }.freeze

      INSTRUCTIONS = <<~TEXT.freeze
        Coordinate checkpointed concurrent development across repositories; the server records facts,
        not Git/CI execution. Load the product entry guide with
        skill_get(name: "coordinator-getting-started", scope: "mcp:concurrent-development-coordinator").
        skill_list with no scope lists static built-in guides covering every server function;
        they require no database, publication or installation. Each entry names its tools.
        An explicit project scope lists stored Skill entities. Tool schemas remain in tools/list.
        Load project-specific Skills/guidance separately; scopes have no implicit precedence.
        Clients need not advertise Tasks support. Ordinary mutations return a durable Task handle
        in structuredContent; persist taskId and poll task_get(task_id: ...) at pollIntervalMs.
        Initial acceptance is not completion. Inspect the terminal result.isError and
        result.structuredContent.completion; a successful receipt needs no entity read-back.
        Reads may lag; commands recheck authoritative facts. Replay the exact command_id/payload
        after an unknown response; changed intent after a known outcome needs a new command_id.
        Cancellation never promises rollback. Actor labels are attribution, not authentication.
        Built-in usage guides ship with the application; agents choose how to use retrieved
        instructions. Project Skills and their assets are ordinary stored knowledge entities.
      TEXT

      def initialize(tasks_extension:)
        @tasks_extension = tasks_extension
      end

      def call
        server = Tasks::Server.new(
          observability: Shared::Observability::McpInvocation.new(inventory: Container["observability.inventory"]),
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
