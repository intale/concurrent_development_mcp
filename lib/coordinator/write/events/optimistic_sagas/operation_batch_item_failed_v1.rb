# frozen_string_literal: true

module Coordinator::Write
  module Events::OptimisticSagas
    class OperationBatchItemFailedV1 < Events::Base
      contract type: "OperationBatchItemFailed", version: 1
      attribute :batch_id, Types::OperationBatchId
      attribute :index, Types::OperationBatchItemIndex
      attribute :failed_step, Types::Identifier
      attribute :reason_code, Types::Identifier
      attribute :reason, Types::String.constrained(min_size: 1, max_size: 2_000)
      attribute :retryable, Types::Strict::Bool
      attribute :effects_committed, Types::Strict::Bool
      attribute :attempts, Types::Integer.constrained(gteq: 1, lteq: 3)
    end
  end
end
