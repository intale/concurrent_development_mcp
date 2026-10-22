# frozen_string_literal: true

module Coordinator::Mcp
  module Tools
    class TaskCancel < ::MCP::Tool
      tool_name "task_cancel"
      title "Request cooperative Task cancellation"
      description <<~TEXT.squish
        Request cancellation of an existing durable Task without requiring the Tasks extension.
        Acknowledgement is not terminal cancellation; execution can race this request. Poll task_get
        for the authoritative outcome. Never rolls back committed effects or cancels related operations.
      TEXT
      input_schema DryStructSchema.new.call(Tasks::TaskReferenceV1)
      output_schema Tasks::ResultSchemas.acknowledgement
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      def self.call(task_id:, server_context: nil)
        result = Coordinator::Container["mcp.tasks.lifecycle"].cancel(taskId: task_id)
        Tasks::ToolResultPresenter.call(
          result,
          note: "Cancellation request acknowledged. Poll task_get for the outcome; acknowledgement does not establish cancellation or rollback."
        )
      end
    end
  end
end
