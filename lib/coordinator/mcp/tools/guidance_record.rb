# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class GuidanceRecord < MutationTool
        tool_name "guidance_record"
        title "Record guidance evidence"
        description "Record deliberately submitted attributed guidance without activating policy."
        input_schema Schemas.guidance_record
        operation "operations.submit_record_guidance_task"
      end
    end
  end
end
