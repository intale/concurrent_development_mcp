# frozen_string_literal: true

module Coordinator::Mcp
  module Tools
    class TaskGet < ::MCP::Tool
      tool_name "task_get"
      title "Get authoritative Task outcome"
      description <<~TEXT.squish
        Poll a durable Task handle without requiring the Tasks extension. Reads authoritative
        write-side facts, not projections. While working, wait pollIntervalMs before polling again.
        Completed does not alone mean success: inspect result.isError and result.structuredContent.completion.
        A successful terminal receipt needs no entity read-back. Failed/cancelled never imply rollback.
      TEXT
      input_schema DryStructSchema.new.call(Tasks::TaskReferenceV1)
      output_schema Tasks::ResultSchemas.detailed
      annotations(read_only_hint: true, idempotent_hint: true, open_world_hint: false)

      def self.call(task_id:, server_context: nil)
        result = Coordinator::Container["mcp.tasks.lifecycle"].get(taskId: task_id)
        Tasks::ToolResultPresenter.call(result)
      end
    end
  end
end
