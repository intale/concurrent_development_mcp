# frozen_string_literal: true

module Coordinator::Mcp
  module Tasks
    class TerminalResultValidator
      def initialize(semantic_presenter: SemanticResultPresenterV1.new)
        @semantic_presenter = semantic_presenter
      end

      def call(state, semantic_result: nil)
        return state unless state.status == "completed"

        tool = ToolRegistry.all.find { _1.tool_name == state.tool_name }
        raise KeyError, "Unknown originating Task tool: #{state.tool_name}" unless tool

        structured_content = completed_structured_content(semantic_result)
        tool.output_schema.validate_result(structured_content.to_h)
        state
      end

      private

      def completed_structured_content(semantic_result)
        raise KeyError, "Completed Task has no authoritative result" unless semantic_result

        @semantic_presenter.call(semantic_result).structuredContent
      end
    end
  end
end
