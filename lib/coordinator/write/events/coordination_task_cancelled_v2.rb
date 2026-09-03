# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CoordinationTaskCancelledV2 < Base
      contract type: "CoordinationTaskCancelled", version: 2

      attribute :task_id, Types::TaskId
      attribute :reason, Types::TaskCancellationReason
    end
  end
end
