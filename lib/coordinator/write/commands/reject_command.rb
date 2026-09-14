# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class RejectCommand < Value
      attribute :command_id, Types::CommandId
      attribute :error, Tasks::DomainErrorV1::Type
      attribute :retryable, Types::Strict::Bool
    end
  end
end
