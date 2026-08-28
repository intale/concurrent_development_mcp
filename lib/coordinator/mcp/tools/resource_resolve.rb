# frozen_string_literal: true

module Coordinator
  module Mcp
    module Tools
      class ResourceResolve < MutationTool
        tool_name "resource_resolve"
        title "Resolve a server-owned Resource identity"
        description <<~TEXT.squish
          Resolve one exact Repository, kind, and relative Git path tuple to a server-generated UUIDv7.
          Supply no Resource UUID, marker, digest, or timestamp. The write-side decision uses only
          authoritative pg_eventstore facts and remains valid while read projections lag or are stopped.
        TEXT
        input_schema Schemas.object_schema(
          properties: Schemas.common_mutation_properties.merge(
            actor: Schemas.agent_actor,
            repository_id: Schemas.uuid_v7.merge(
              description: "Previously registered canonical Repository UUID."
            ),
            kind: { type: "string", enum: %w[file directory] },
            path: Schemas.utf8_text(maximum_bytes: 1_024).merge(
              description: "Relative Git path normalized and validated by the server."
            )
          ),
          required: %w[command_id actor repository_id kind path]
        )
        operation "operations.submit_resolve_resource_task"
      end
    end
  end
end
