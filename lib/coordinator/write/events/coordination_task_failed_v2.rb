# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CoordinationTaskFailedV2 < Base
      contract type: "CoordinationTaskFailed", version: 2

      attribute :task_id, Types::TaskId
      attribute :code, Types::Identifier
      attribute :reason, Types::TaskFailureReason
      attribute :retryable, Types::Strict::Bool
    end
  end
end
