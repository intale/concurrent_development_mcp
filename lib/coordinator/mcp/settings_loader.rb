# frozen_string_literal: true

module Coordinator
  module Mcp
    class SettingsLoader
      def initialize(contract: Contracts::McpSettings.new)
        @contract = contract
      end

      def call(environment = ENV)
        result = @contract.call(
          allowed_hosts: comma_separated(environment["MCP_ALLOWED_HOSTS"]),
          allowed_origins: comma_separated(environment["MCP_ALLOWED_ORIGINS"]),
          max_request_bytes: environment.fetch("MCP_MAX_REQUEST_BYTES", "4194304")
        )
        raise ArgumentError, "MCP settings are invalid: #{result.errors.to_h.inspect}" if result.failure?

        Settings.new(result.to_h)
      end

      private

      def comma_separated(value)
        value.to_s.split(",").map(&:strip).reject(&:empty?).uniq
      end
    end
  end
end
