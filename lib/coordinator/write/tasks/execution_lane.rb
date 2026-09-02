# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    class ExecutionLane
      COUNT = 2
      MARKER_PREFIX = "task-execution-lane:v2:"

      def index(task_id)
        uuid = Types::UuidV7[task_id]
        uuid.delete("-").last(8).to_i(16).modulo(COUNT)
      end

      def marker(task_id)
        marker_for(index(task_id))
      end

      def marker_for(index)
        "#{MARKER_PREFIX}#{index}"
      end
    end
  end
end
