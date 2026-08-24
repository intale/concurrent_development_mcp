# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class ReleaseActivationRecord < MutationTool
        tool_name "release_activation_record"
        title "Record a ReleaseSet activation"
        description "Record attributed external activation evidence for an exactly verified ReleaseSet."
        input_schema Schemas.release_activation_record
        operation "operations.submit_record_release_set_activation_task"
      end
    end
  end
end
