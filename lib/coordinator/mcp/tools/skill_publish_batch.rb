# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class SkillPublishBatch < MutationTool
        tool_name "skill_publish_batch"
        title "Publish a bounded batch of scoped AI skill revisions"
        description "Accept 1..1,000 ordinary skill_publish commands for ordered asynchronous Saga processing. Each item commits or is rejected independently."
        input_schema Schemas.skill_publish_batch
        operation "operations.submit_create_skill_publish_batch_task"
      end
    end
  end
end
