# frozen_string_literal: true

module Coordinator::Write
  module Events
    class OperationBatchCancellationRequestedV2 < Base
      contract type: "OperationBatchCancellationRequested", version: 2

      attribute :batch_id, Types::OperationBatchId
    end
  end
end
