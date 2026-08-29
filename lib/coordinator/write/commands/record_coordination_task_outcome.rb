# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class RecordCoordinationTaskOutcome < Value
      attribute :task_id, Types::TaskId
      attribute :outcome, Tasks::OutcomeV2::Type
      attribute :recorded_at, Types::Timestamp
    end
  end
end
