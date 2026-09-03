# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CommandRejectedV1 < Base
      contract type: "CommandRejected", version: 1

      attribute :command_id, Types::CommandId
      attribute :code, Types::Identifier
      attribute :reason, Types::String.constrained(min_size: 1, max_size: 2_000)
      attribute :retryable, Types::Strict::Bool
    end
  end
end
