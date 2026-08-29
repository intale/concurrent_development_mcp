# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class WriteSetReserve < MutationTool
        tool_name "write_set_reserve"
        title "Reserve a Resource write set"
        description "Atomically reserve an Attempt's complete initial Resource-ID write set at its exact repository base."
        input_schema Schemas.write_set_reserve
        operation "operations.submit_reserve_write_set_task"
      end
    end
  end
end
