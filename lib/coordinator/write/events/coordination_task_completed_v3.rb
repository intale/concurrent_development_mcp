# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CoordinationTaskCompletedV3 < Base
      contract type: "CoordinationTaskCompleted", version: 3

      attribute :task_id, Types::TaskId
    end
  end
end
