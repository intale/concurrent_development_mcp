# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CoordinationTaskCancelledV1 < Base
      contract type: "CoordinationTaskCancelled", version: 1

      attribute :task_id, Types::TaskId
      attribute :reason, Types::String.enum("cancelled_before_execution")
      attribute :cancelled_at, Types::Timestamp
    end
  end
end
