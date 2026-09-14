# frozen_string_literal: true

module Coordinator::Write
  module OperationBatches
    class RejectionV1 < Value
      attribute :code, Types::Identifier
      attribute :reason, Types::String.constrained(min_size: 1, max_size: 2_000)
      attribute :retryable, Types::Strict::Bool
    end
  end
end
