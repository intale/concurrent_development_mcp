# frozen_string_literal: true

module Coordinator::Write::Commands
  class FailCommand < Coordinator::Shared::Value
    attribute :command_id, Coordinator::Write::Types::CommandId
    attribute :failure, Coordinator::Write::Tasks::ExecutionFailureV1
  end
end
