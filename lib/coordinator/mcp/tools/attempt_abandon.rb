# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class AttemptAbandon < MutationTool
        tool_name "attempt_abandon"
        title "Abandon an Attempt and requeue its WorkItem"
        description <<~TEXT.squish
          Atomically abandon an active Attempt without a Candidate, release only lease fences still owned by it,
          and requeue its WorkItem for acquisition through a fresh Attempt and base snapshot.
        TEXT
        input_schema Schemas.attempt_abandon
        operation "operations.submit_abandon_attempt_task"
      end
    end
  end
end
