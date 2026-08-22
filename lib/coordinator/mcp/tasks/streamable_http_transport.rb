# frozen_string_literal: true

module Coordinator::Mcp
  module Tasks
    class StreamableHttpTransport < ::MCP::Server::Transports::StreamableHTTPTransport
      TASK_METHODS = [
        Extension::GET_METHOD,
        Extension::UPDATE_METHOD,
        Extension::CANCEL_METHOD
      ].freeze

      private

      def validate_modern_headers(request, body, header_version)
        validation = super
        return validation if validation
        return unless TASK_METHODS.include?(body[:method])

        params = body[:params]
        task_id = params[:taskId] if params.is_a?(Hash)
        return unless task_id

        name_header = request.env["HTTP_MCP_NAME"]
        if name_header.to_s.empty?
          return header_mismatch_response(
            "Mcp-Name header is required for `#{body[:method]}`",
            body[:id]
          )
        end

        decoded_name = decode_header_value(name_header)
        return if decoded_name == task_id

        header_mismatch_response(
          "Mcp-Name header value '#{decoded_name}' does not match body value '#{task_id}'",
          body[:id]
        )
      end
    end
  end
end
