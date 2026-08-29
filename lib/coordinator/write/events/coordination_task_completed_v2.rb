# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CoordinationTaskCompletedV2 < Base
      contract type: "CoordinationTaskCompleted", version: 2

      attribute :task_id, Types::TaskId
      attribute :result, Tasks::SemanticResultV1::Type
      attribute :completed_at, Types::Timestamp
    end
  end
end
