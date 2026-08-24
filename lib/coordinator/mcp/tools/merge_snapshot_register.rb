# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class MergeSnapshotRegister < MutationTool
        tool_name "merge_snapshot_register"
        title "Register an attributed external merge snapshot"
        description "Register one exact ordered Candidate composition and external merge-commit attribution. " \
                    "The coordinator validates immutable event evidence but does not inspect Git."
        input_schema Schemas.merge_snapshot_register
        operation "operations.submit_register_merge_snapshot_task"
      end
    end
  end
end
