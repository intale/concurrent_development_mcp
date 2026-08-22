# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CoordinationTaskCompletedV1 < Base
      contract type: "CoordinationTaskCompleted", version: 1

      attribute :task_id, Types::TaskId
      attribute :result, Tasks::ToolResultV1
      attribute :completed_at, Types::Timestamp
    end
  end
end
