# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class MergeVerificationSubmit < MutationTool
        tool_name "merge_verification_submit"
        title "Submit exact merge-snapshot verification evidence"
        description "Submit attributed combined-test evidence bound to one registered merge snapshot. " \
                    "A qualifying pass verifies the exact snapshot atomically with the evidence fact."
        input_schema Schemas.merge_verification_submit
        operation "operations.submit_merge_snapshot_verification_task"
      end
    end
  end
end
