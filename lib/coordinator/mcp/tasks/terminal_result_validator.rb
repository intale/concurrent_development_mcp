# frozen_string_literal: true

module Coordinator::Mcp
  module Tasks
    class TerminalResultValidator
      def call(state)
        return state unless state.status == "completed"

        tool = ToolRegistry.all.find { _1.tool_name == state.tool_name }
        raise KeyError, "Unknown originating Task tool: #{state.tool_name}" unless tool

        tool.output_schema.validate_result(state.result.structured_content.to_h)
        state
      end
    end
  end
end
