# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CoordinationTaskCancellationRequestedV2 < Base
      contract type: "CoordinationTaskCancellationRequested", version: 2

      attribute :task_id, Types::TaskId
      attribute :reason, Types::TaskCancellationReason.optional
    end
  end
end
