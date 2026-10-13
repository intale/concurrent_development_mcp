# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class SkillPublishBatch < MutationTool
        tool_name "skill_publish_batch"
        title "Publish a bounded batch of scoped AI skill revisions"
        description "Bulk-import 1..1,000 caller-discovered complete Skill revisions within the 3-MiB canonical-input limit. Initial Task acceptance records the manifest only; poll tasks/get until the whole bounded Saga settles. The final result reports successes, denials, failures and items not run; earlier successes are never rolled back. Child request IDs bind independently; exact existing requests reuse their result, changed input rejects only that item. operation_batch_get is optional projected per-item context, not persistence confirmation."
        input_schema Schemas.skill_publish_batch
        operation "operations.submit_create_skill_publish_batch_task"
      end
    end
  end
end
