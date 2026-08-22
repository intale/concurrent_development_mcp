# frozen_string_literal: true

module Coordinator::Mcp
  module Tasks
    class RequestError < ::MCP::Server::RequestHandlerError
      MISSING_CAPABILITY_CODE = -32_003
      INVALID_PARAMS_CODE = -32_602
      INTERNAL_ERROR_CODE = -32_603

      class << self
        def missing_capability(request)
          new(
            "Missing required client capability",
            request,
            error_type: :missing_required_client_capability,
            error_code: MISSING_CAPABILITY_CODE,
            error_data: { requiredCapabilities: Capability::REQUIRED_CAPABILITIES }
          )
        end

        def invalid_task_request(errors, request)
          new(
            "Invalid Task request",
            request,
            error_type: :invalid_params,
            error_code: INVALID_PARAMS_CODE,
            error_data: errors
          )
        end

        def operation_failure(error, request)
          case error
          when Coordinator::Write::Tasks::LifecycleError
            lifecycle_failure(error, request)
          when Coordinator::Write::OutcomeError
            invalid_task_request(
              { code: error.code, message: error.message, details: error.details },
              request
            )
          else
            internal_failure(request)
          end
        end

        private

        def lifecycle_failure(error, request)
          if error.code == :task_not_found
            return invalid_task_request(
              { code: error.code, message: error.message, taskId: error.task_id },
              request
            )
          end

          internal_failure(
            request,
            data: {
              code: error.code,
              message: error.message,
              retryable: error.code == :concurrency_conflict,
              taskId: error.task_id
            }
          )
        end

        def internal_failure(request, data: nil)
          new(
            "Task operation could not be completed",
            request,
            error_type: :internal_error,
            error_code: INTERNAL_ERROR_CODE,
            error_data: data
          )
        end
      end
    end
  end
end
