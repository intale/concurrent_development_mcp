# frozen_string_literal: true

module Coordinator::Write::Tasks
  class ExecutionFailureV1 < Coordinator::Shared::Value
    attribute :failed_step, Coordinator::Write::Types::Identifier
    attribute :reason_code, Coordinator::Write::Types::Identifier
    attribute :reason, Coordinator::Write::Types::String.constrained(min_size: 1, max_size: 2_000)
    attribute :retryable, Coordinator::Write::Types::Strict::Bool
    attribute :effects_committed, Coordinator::Write::Types::Strict::Bool
    attribute :attempts, Coordinator::Write::Types::Integer.constrained(gteq: 1, lteq: 3)
  end
end
