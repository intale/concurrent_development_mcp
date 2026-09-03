# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class RecordCoordinationTaskOutcome < Value
      attribute :task_id, Types::TaskId
      attribute :outcome, Tasks::OutcomeV2::Type
    end
  end
end
