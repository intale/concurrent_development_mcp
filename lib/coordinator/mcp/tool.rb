# frozen_string_literal: true

module Coordinator
  module Mcp
    class Tool < ::MCP::Tool
      output_schema Schemas.envelope

      class << self
        def inherited(subclass)
          super
          subclass.output_schema Schemas.envelope
        end

        private

        def invoke(operation_key, arguments)
          result = Container[operation_key].call(arguments)
          payload = ResultMapper.new.call(result, command_id: arguments[:command_id])
          response(payload)
        rescue StandardError => error
          Rails.error.report(error, handled: true)
          response(unexpected_failure, error: true)
        end

        def response(result, error: false)
          payload = result.to_h
          output_schema.validate_result(payload)
          ::MCP::Tool::Response.new(
            [ { type: "text", text: JSON.generate(payload) } ],
            structured_content: payload,
            error:
          )
        end

        def unexpected_failure
          McpResultV1.new(
            status: "invalid",
            summary: "The coordinator could not complete the request.",
            command_id: nil,
            receipt: nil,
            context_token: nil,
            data: McpResultV1::DomainError.new(
              code: "internal_error",
              message: "An unexpected coordinator error occurred",
              details: {}
            ),
            warnings: [],
            next_actions: [],
            projection_status: nil
          )
        end
      end
    end
  end
end
