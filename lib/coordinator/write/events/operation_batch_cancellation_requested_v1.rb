# frozen_string_literal: true

module Coordinator::Write
  module Events
    class OperationBatchCancellationRequestedV1 < Base
      contract type: "OperationBatchCancellationRequested", version: 1

      attribute :batch_id, Types::OperationBatchId
      attribute :requester, OperationBatches::ActorV1
      attribute :requested_at, Types::Timestamp
    end
  end
end
