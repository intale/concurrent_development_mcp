# frozen_string_literal: true

module Coordinator::Write
  module Events
    class OperationBatchItemRegistrationRejectedV1 < Base
      contract type: "OperationBatchItemRegistrationRejected", version: 1

      attribute :batch_id, Types::OperationBatchId
      attribute :index, Types::OperationBatchItemIndex
      attribute :error, Tasks::DomainErrorV1::Type
    end
  end
end
