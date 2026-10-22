# frozen_string_literal: true

module Coordinator::Mcp
  module Tasks
    class ToolResultPresenter
      def self.call(result, note: nil)
        payload = result.to_h
        content = [ { type: "text", text: JSON.generate(payload) } ]
        content << { type: "text", text: note } if note
        ::MCP::Tool::Response.new(content, structured_content: payload)
      end
    end
  end
end
