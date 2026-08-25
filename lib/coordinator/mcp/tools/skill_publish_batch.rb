# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class SkillPublishBatch < MutationTool
        tool_name "skill_publish_batch"
        title "Publish a bounded batch of scoped AI skill revisions"
        description "Bulk-import 1..1,000 caller-discovered complete Skill revisions within the 3-MiB canonical-input limit. The asynchronous Saga runs ordinary skill_publish commands; each item commits or is rejected independently."
        input_schema Schemas.skill_publish_batch
        operation "operations.submit_create_skill_publish_batch_task"
      end
    end
  end
end
