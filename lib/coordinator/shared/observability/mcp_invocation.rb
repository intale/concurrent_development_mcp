# frozen_string_literal: true

module Coordinator::Shared
  module Observability
    class McpInvocation
      def initialize(inventory:)
        @inventory = inventory
      end

      def call(request)
        session = Runtime.current
        return yield unless session

        invocation = Runtime.safely(:mcp_invocation) do
          attributes = request_attributes(request)
          Invocation.new(session:, prefix: :mcp, name: "mcp #{attributes.fetch('rpc.method')}", attributes:)
        end
        invocation ? invocation.call(outcome: McpOutcome.method(:call)) { yield } : yield
      end

      private

      def request_attributes(request)
        request = JSON.parse(request) if request.is_a?(String)
        request = {} unless request.is_a?(Hash)
        method = request["method"] || request[:method]
        params = request["params"] || request[:params]
        tool = params["name"] || params[:name] if params.is_a?(Hash)
        @inventory.mcp_attributes(method: method.is_a?(String) ? method : nil, tool_name: tool.is_a?(String) ? tool : nil)
      rescue JSON::ParserError
        @inventory.mcp_attributes(method: nil)
      end
    end
  end
end
