# frozen_string_literal: true

module Coordinator::Shared
  module Observability
    module McpOutcome
      module_function

      def call(response)
        response = JSON.parse(response) if response.is_a?(String)
        return "ok" if response.nil?

        error = value(response, "error")
        return error_outcome(error) if error

        result = value(response, "result")
        return "unknown" unless result.is_a?(Hash)
        return "accepted" if value(result, "resultType") == "task"

        status = value(result, "status")
        return "pending" if %w[working input_required].include?(status)
        return "cancelled" if status == "cancelled"
        return "error" if status == "failed"

        semantic = value(result, "structuredContent") || value(value(result, "result"), "structuredContent")
        return Contract.outcome(value(semantic, "status")) if semantic

        # Native schema errors expose only isError and human text. Count the
        # error without parsing that text or copying it into telemetry.
        value(result, "isError") ? "error" : "ok"
      end

      def error_outcome(error)
        return "not_found" if value(value(error, "data"), "code") == "task_not_found"

        case value(error, "code")
        when -32_700, -32_600, -32_602 then "invalid"
        when -32_601 then "not_found"
        when -32_003 then "denied"
        else "error"
        end
      end
      private_class_method :error_outcome

      def value(object, key)
        object[key] || object[key.to_sym] if object.is_a?(Hash)
      end
      private_class_method :value
    end
  end
end
