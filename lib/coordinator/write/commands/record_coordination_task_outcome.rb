# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class RecordCoordinationTaskOutcome < Value
      attribute :task_id, Types::TaskId
      Outcome = Tasks::OutcomeV1::Type | Tasks::OutcomeV2::Type

      attribute :outcome, Outcome
      attribute :recorded_at, Types::Timestamp
    end
  end
end
