# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CommandRejectedV2 < Base
      contract type: "CommandRejected", version: 2

      attribute :command_id, Types::CommandId
      attribute :error, Tasks::DomainErrorV1::Type
      attribute :retryable, Types::Strict::Bool
    end
  end
end
