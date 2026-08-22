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
      end
    end
  end
end
