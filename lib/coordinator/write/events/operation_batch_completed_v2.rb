# frozen_string_literal: true

module Coordinator::Write
  module Events
    class OperationBatchCompletedV2 < Base
      contract type: "OperationBatchCompleted", version: 2

      attribute :batch_id, Types::OperationBatchId
    end
  end
end
