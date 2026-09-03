# frozen_string_literal: true

module Coordinator::Write
  module Events
    class OperationBatchCancelledV2 < Base
      contract type: "OperationBatchCancelled", version: 2

      attribute :batch_id, Types::OperationBatchId
    end
  end
end
