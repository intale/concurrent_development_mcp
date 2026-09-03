# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CoordinationTaskExecutionStartedV2 < Base
      contract type: "CoordinationTaskExecutionStarted", version: 2

      attribute :task_id, Types::TaskId
    end
  end
end
