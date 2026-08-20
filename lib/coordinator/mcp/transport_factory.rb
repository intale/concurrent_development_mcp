# frozen_string_literal: true

module Coordinator
  module Mcp
    class TransportFactory
      def call(server:, settings:)
        ::MCP::Server::Transports::StreamableHTTPTransport.new(
          server,
          stateless: true,
          enable_json_response: true,
          allowed_hosts: settings.allowed_hosts,
          allowed_origins: settings.allowed_origins,
          max_request_bytes: settings.max_request_bytes
        )
      end
    end
  end
end
