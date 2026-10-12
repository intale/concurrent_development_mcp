# frozen_string_literal: true

module Coordinator::Write::Events::OptimisticSagas
  class CommandExecutionFailedV1 < Coordinator::Write::Events::Base
    contract type: "CommandExecutionFailed", version: 1

    attribute :command_id, Coordinator::Shared::Types::CommandId
    attribute :failed_step, Coordinator::Shared::Types::Identifier
    attribute :reason_code, Coordinator::Shared::Types::Identifier
    attribute :reason, Coordinator::Shared::Types::String.constrained(min_size: 1, max_size: 2_000)
    attribute :retryable, Coordinator::Shared::Types::Strict::Bool
    attribute :effects_committed, Coordinator::Shared::Types::Strict::Bool
    attribute :attempts, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 3)
  end
end
