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
          invoke(operation, arguments)
        end
      end
    end
  end
end
