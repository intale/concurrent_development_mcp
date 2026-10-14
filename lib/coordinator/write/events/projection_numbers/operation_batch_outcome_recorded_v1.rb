# frozen_string_literal: true

module Coordinator::Write::Events::ProjectionNumbers
  class OperationBatchOutcomeRecordedV1 < Coordinator::Write::Events::Base
    contract type: "OperationBatchOutcomeRecorded", version: 1

    attribute :batch_id, Coordinator::Write::Types::OperationBatchId
    attribute :outcome, Coordinator::Write::Types::String.enum("completed", "completed_with_errors", "cancelled")
  end
end
