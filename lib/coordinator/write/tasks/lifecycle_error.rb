# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    class LifecycleError < Value
      attribute :code, Types::Symbol.enum(
        :task_not_found,
        :task_id_collision,
        :task_not_started,
        :concurrency_conflict
      )
      attribute :message, Types::String
      attribute :task_id, Types::TaskId
    end
  end
end
