# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CoordinationTaskExecutionStartedV1 < Base
      contract type: "CoordinationTaskExecutionStarted", version: 1

      attribute :task_id, Types::TaskId
      attribute :started_at, Types::Timestamp
    end
  end
end
