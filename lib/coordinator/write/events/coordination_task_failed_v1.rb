# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CoordinationTaskFailedV1 < Base
      contract type: "CoordinationTaskFailed", version: 1

      attribute :task_id, Types::TaskId
      attribute :error, Tasks::JsonRpcErrorV1
      attribute :failed_at, Types::Timestamp
    end
  end
end
