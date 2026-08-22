# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class CancelCoordinationTask < Value
      attribute :task_id, Types::TaskId
      attribute :requested_at, Types::Timestamp
    end
  end
end
