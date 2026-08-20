# frozen_string_literal: true

module Coordinator
  module Mcp
    class QueryTool < Tool
      annotations(
        read_only_hint: true,
        destructive_hint: false,
        idempotent_hint: true,
        open_world_hint: false
      )

      class << self
        def inherited(subclass)
          super
          subclass.annotations(
            read_only_hint: true,
            destructive_hint: false,
            idempotent_hint: true,
            open_world_hint: false
          )
        end

        def query(key = nil)
          return @query_key unless key

          @query_key = key
        end

        def call(server_context: nil, **arguments)
          invoke(query, arguments)
        end
      end
    end
  end
end
