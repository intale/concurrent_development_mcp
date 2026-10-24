# frozen_string_literal: true

module Coordinator::Mcp
  module UsageSkills
    class InstallError < StandardError
      attr_reader :task_id

      def initialize(message, task_id: nil)
        @task_id = task_id
        super(message)
      end
    end
  end
end
