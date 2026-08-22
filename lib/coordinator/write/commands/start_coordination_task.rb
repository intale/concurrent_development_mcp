# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class StartCoordinationTask < Value
      attribute :task_id, Types::TaskId
      attribute :started_at, Types::Timestamp
    end
  end
end
