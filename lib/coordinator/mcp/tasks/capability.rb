# frozen_string_literal: true

module Coordinator::Mcp
  module Tasks
    module Capability
      EXTENSION_ID = "io.modelcontextprotocol/tasks"
      EXTENSIONS = { EXTENSION_ID => {}.freeze }.freeze
      REQUIRED_CAPABILITIES = { extensions: EXTENSIONS }.freeze

      module_function

      def require!(capabilities, modern:, request:)
        return if modern && declared?(capabilities)

        raise RequestError.missing_capability(request)
      end

      def declared?(capabilities)
        return false unless capabilities

        extensions = capabilities[:extensions] || capabilities["extensions"]
        return false unless extensions.is_a?(Hash)

        value = extensions[EXTENSION_ID] || extensions[EXTENSION_ID.to_sym]
        value.is_a?(Hash)
      end
    end
  end
end
