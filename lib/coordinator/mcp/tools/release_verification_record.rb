# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class ReleaseVerificationRecord < MutationTool
        tool_name "release_verification_record"
        title "Record exact composite ReleaseSet verification"
        description "Record attributed composite evidence bound to the exact successful repository integrations."
        input_schema Schemas.release_verification_record
        operation "operations.submit_record_release_set_verification_task"
      end
    end
  end
end
