# frozen_string_literal: true

module Coordinator
  module Mcp
    class MutationTool < Tool
      annotations(
        read_only_hint: false,
        destructive_hint: false,
        idempotent_hint: true,
        open_world_hint: false
      )

      class << self
        def to_h
          super.merge(outputSchema: resolved_output_schema.to_h)
        end

        def output_schema(value = :__coordinator_not_set__)
          return super(value) unless value == :__coordinator_not_set__

          resolved_output_schema
        end

        def inherited(subclass)
          super
          subclass.annotations(
            read_only_hint: false,
            destructive_hint: false,
            idempotent_hint: true,
            open_world_hint: false
          )
        end

        def operation(key = nil)
          return @operation_key unless key

          @operation_key = key
        end

        def call(server_context: nil, **arguments)
          result = Container[operation].call(arguments)
          raise Tasks::RequestError.operation_failure(result.failure, arguments) if result.failure?

          Container["mcp.tasks.result_mapper"].created(result.value!)
        end

        private

        def resolved_output_schema
          @resolved_output_schema ||= ::MCP::Tool::OutputSchema.new(MutationResultSchemas.for(tool_name))
        end
      end
    end
  end
end
