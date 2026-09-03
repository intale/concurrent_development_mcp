# frozen_string_literal: true

module Coordinator::Mcp
  module Tasks
    class Extension
      GET_METHOD = "tasks/get"
      UPDATE_METHOD = "tasks/update"
      CANCEL_METHOD = "tasks/cancel"

      def initialize(
        get_task:,
        acknowledge_task_input:,
        cancel_task:,
        result_mapper: ResultMapper.new,
        projected_result_resolver: ProjectedResultResolver.new,
        terminal_result_validator: TerminalResultValidator.new,
        get_contract: Contracts::GetTaskRequest.new,
        update_contract: Contracts::UpdateTaskRequest.new,
        cancel_contract: Contracts::CancelTaskRequest.new
      )
        @get_task = get_task
        @acknowledge_task_input = acknowledge_task_input
        @cancel_task = cancel_task
        @result_mapper = result_mapper
        @projected_result_resolver = projected_result_resolver
        @terminal_result_validator = terminal_result_validator
        @get_contract = get_contract
        @update_contract = update_contract
        @cancel_contract = cancel_contract
      end

      def register(server)
        server.define_custom_method(method_name: GET_METHOD, &method(:get_task))
        server.define_custom_method(method_name: UPDATE_METHOD, &method(:update_task))
        server.define_custom_method(method_name: CANCEL_METHOD, &method(:cancel_task))
        server
      end

      private

      def get_task(params, server_context:)
        require_capability!(server_context, params)
        attributes = validate(@get_contract, params)
        state = operation_value(
          @get_task.call(task_id: attributes.fetch(:taskId)),
          params
        )

        projected_result = @projected_result_resolver.call(state) if state.status == "completed"
        @terminal_result_validator.call(state, projected_result:)
        @result_mapper.detailed(state, projected_result:).to_h
      end

      def update_task(params, server_context:)
        require_capability!(server_context, params)
        attributes = validate(@update_contract, params)
        operation_value(
          @acknowledge_task_input.call(task_id: attributes.fetch(:taskId)),
          params
        )

        @result_mapper.acknowledgement.to_h
      end

      def cancel_task(params, server_context:)
        require_capability!(server_context, params)
        attributes = validate(@cancel_contract, params)
        operation_value(
          @cancel_task.call(task_id: attributes.fetch(:taskId)),
          params
        )

        @result_mapper.acknowledgement.to_h
      end

      def require_capability!(server_context, request)
        Capability.require!(
          server_context.client_capabilities,
          modern: server_context.modern?,
          request:
        )
      end

      def validate(contract, params)
        result = contract.call(params)
        return result.to_h if result.success?

        raise RequestError.invalid_task_request(result.errors.to_h, params)
      end

      def operation_value(result, request)
        return result.value! if result.success?

        raise RequestError.operation_failure(result.failure, request)
      end
    end
  end
end
