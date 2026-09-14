# frozen_string_literal: true

module Coordinator::Write
  module Events
    class OperationBatchCreatedV2 < Base
      contract type: "OperationBatchCreated", version: 2

      attribute :batch_id, Types::OperationBatchId
    end
  end
end
