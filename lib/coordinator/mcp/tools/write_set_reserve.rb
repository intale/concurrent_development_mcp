# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class WriteSetReserve < MutationTool
        tool_name "write_set_reserve"
        title "Reserve a file write set"
        description "Atomically reserve an Attempt's complete initial file write set at its exact repository base."
        input_schema Schemas.write_set_reserve
        operation "operations.submit_reserve_write_set_task"
      end
    end
  end
end
