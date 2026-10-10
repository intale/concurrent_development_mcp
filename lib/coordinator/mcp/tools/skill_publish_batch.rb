# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class SkillPublishBatch < MutationTool
        tool_name "skill_publish_batch"
        title "Publish a bounded batch of scoped AI skill revisions"
        description "Bulk-import 1..1,000 caller-discovered complete Skill revisions within the 3-MiB canonical-input limit. The Task accepts the manifest, not all child request IDs. The Saga binds and runs ordinary skill_publish commands independently; identical existing requests reuse their result, changed request inputs reject only that item. Poll operation_batch_get for each outcome."
        input_schema Schemas.skill_publish_batch
        operation "operations.submit_create_skill_publish_batch_task"
      end
    end
  end
end
