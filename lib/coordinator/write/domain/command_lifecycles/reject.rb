# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module CommandLifecycles
      class Reject
        include Dry::Monads[:result]

        def call(state:, command:)
          return Failure(command_not_found(command.command_id)) if state.absent?
          return Failure(terminal_conflict(state)) if state.succeeded?
          return reject_registered(command) unless state.rejected?
          return Success(nil) if same_rejection?(state, command)

          Failure(contradictory_rejection(state, command))
        end

        private

        def reject_registered(command)
          Success(
            Events::CommandRejectedV2.new(
              command_id: command.command_id,
              error: command.error,
              retryable: command.retryable
            )
          )
        end

        def same_rejection?(state, command)
          state.rejection_code == command.error.code &&
            state.rejection_reason == command.error.message &&
            state.rejection_retryable == command.retryable
        end

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
            message: "Command is already successful",
            details: { command_id: state.command_id, status: state.status }
          )
        end

        def contradictory_rejection(state, command)
          OutcomeError.new(
            code: :command_terminal,
            message: "Command is already rejected with another outcome",
            details: {
              command_id: state.command_id,
              existing_code: state.rejection_code,
              requested_code: command.error.code
            }
          )
        end
      end
    end
  end
end
