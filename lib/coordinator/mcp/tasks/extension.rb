# frozen_string_literal: true

module Coordinator::Mcp
  module Tasks
    class Extension
      CAPABILITIES = { "io.modelcontextprotocol/tasks" => {}.freeze }.freeze
      GET_METHOD = "tasks/get"
      UPDATE_METHOD = "tasks/update"
      CANCEL_METHOD = "tasks/cancel"

      def self.negotiated?(server_context)
        return false unless server_context&.modern?

        capabilities = server_context.client_capabilities
        return false unless capabilities.is_a?(Hash)

        extensions = capabilities["extensions"] || capabilities[:extensions]
        return false unless extensions.is_a?(Hash)

        declaration = extensions["io.modelcontextprotocol/tasks"] || extensions[:"io.modelcontextprotocol/tasks"]
        declaration.is_a?(Hash)
      end

      def initialize(lifecycle:)
        @lifecycle = lifecycle
      end

      def register(server)
        server.define_custom_method(method_name: GET_METHOD) do |params, server_context:|
          @lifecycle.get(params).to_h
        end
        server.define_custom_method(method_name: UPDATE_METHOD) do |params, server_context:|
          @lifecycle.update(params).to_h
        end
        server.define_custom_method(method_name: CANCEL_METHOD) do |params, server_context:|
          @lifecycle.cancel(params).to_h
        end
        server
      end
    end
  end
end
