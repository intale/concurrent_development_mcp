# frozen_string_literal: true

module Coordinator
  module Mcp
    module NextActionSchemas
      TARGET_TOOL_NAMES = %w[
        agent_choice_get
        attempt_list
        candidate_get
        coord_context
        coordination_list
        decision_get
        decision_interpretation_list
        decision_list
        decision_resolve
        development_artifact_content_get
        development_artifact_get
        development_artifact_locator_resolve
        guidance_get
        merge_snapshot_get
        operation_batch_get
        release_set_get
        repository_list
        skill_get
        verification_obligations_list
      ].freeze

      module_function

      def schema
        {
          oneOf: TARGET_TOOL_NAMES.map { action_schema(_1) }
        }
      end

      def action_schema(tool_name)
        tool = ToolRegistry.all.find { _1.tool_name == tool_name }
        raise KeyError, "Unknown next-action tool: #{tool_name}" unless tool

        Schemas.object_schema(
          properties: {
            tool: { const: tool_name },
            arguments: nested_schema(tool.input_schema.to_h)
          },
          required: %w[tool arguments]
        )
      end

      def nested_schema(schema)
        schema.except(:"$schema", "$schema")
      end
    end
  end
end
