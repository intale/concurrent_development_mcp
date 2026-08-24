# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class MergeObservationRecord < MutationTool
        tool_name "merge_observation_record"
        title "Record an exact external merge observation"
        description "Record a caller-attributed target transition after authoritatively rechecking the exact grant."
        input_schema Schemas.merge_observation_record
        operation "operations.submit_record_merge_observation_task"
      end
    end
  end
end
