# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class ResourceRemove < MutationTool
        tool_name "resource_remove"
        title "Remove a current Resource binding"
        description <<~TEXT.squish
          Explicitly deactivate one server-owned Resource UUID before a delete, rename, or kind change.
          The command derives the exact registered tuple and current-path marker from authoritative
          pg_eventstore facts. Repeating removal is an idempotent zero-fact outcome; no Saga resolves
          a replacement path implicitly.
        TEXT
        input_schema Schemas.object_schema(
          properties: Schemas.common_mutation_properties.merge(
            actor: Schemas.agent_actor,
            resource_id: Schemas.uuid_v7.merge(
              description: "Server-owned Resource UUID returned by resource_resolve."
            ),
            reason: {
              type: "string",
              enum: %w[removed renamed type_changed],
              description: "Why this exact Resource tuple is no longer current."
            }
          ),
          required: %w[command_id actor resource_id reason]
        )
        operation "operations.submit_remove_resource_task"
      end
    end
  end
end
