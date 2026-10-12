# frozen_string_literal: true

module Coordinator::Write::Domain::CommandLifecycles
  class Fail
    include Dry::Monads[:result]

    def call(state:, command:)
      return Failure(Coordinator::Write::OutcomeError.new(
        code: :command_not_found, message: "Command does not exist",
        details: { command_id: command.command_id }
      )) if state.absent?
      return Success(nil) if state.failed? && state.execution_failure == command.failure
      return Failure(Coordinator::Write::OutcomeError.new(
        code: :command_terminal, message: "Command already has another terminal outcome",
        details: { command_id: command.command_id, status: state.status }
      )) if state.terminal?

      Success(Coordinator::Write::Events::OptimisticSagas::CommandExecutionFailedV1.new(
        command_id: command.command_id, **command.failure.to_h
      ))
    end
  end
end
