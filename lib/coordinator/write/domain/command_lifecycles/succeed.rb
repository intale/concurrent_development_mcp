# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module CommandLifecycles
      class Succeed
        include Dry::Monads[:result]

        def call(state:, command:)
          return Failure(command_not_found(command.command_id)) if state.absent?
          return Success(nil) if state.succeeded?
          return Failure(terminal_conflict(state)) if state.rejected?

          Success(Events::CommandSucceededV1.new(command_id: command.command_id))
        end

        private

        def command_not_found(command_id)
          OutcomeError.new(
            code: :command_not_found,
            message: "Command does not exist",
            details: { command_id: }
          )
        end

        def terminal_conflict(state)
          OutcomeError.new(
            code: :command_terminal,
            message: "Command is already rejected",
            details: { command_id: state.command_id, status: state.status }
          )
        end
      end
    end
  end
end
