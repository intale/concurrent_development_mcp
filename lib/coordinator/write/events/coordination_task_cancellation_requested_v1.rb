# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CoordinationTaskCancellationRequestedV1 < Base
      contract type: "CoordinationTaskCancellationRequested", version: 1

      attribute :task_id, Types::TaskId
      attribute :requested_at, Types::Timestamp
    end
  end
end
