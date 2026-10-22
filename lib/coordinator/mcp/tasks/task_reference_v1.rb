# frozen_string_literal: true

module Coordinator::Mcp
  module Tasks
    class TaskReferenceV1 < Value
      attribute :task_id, Types::TaskId
    end
  end
end
