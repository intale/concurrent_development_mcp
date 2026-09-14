# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module ProcessSteps
      class RecordDispatchFailure
        include Dry::Monads[:result]

        def call(state:, command:)
          return Failure(target_mismatch(state, command)) unless target_matches?(state, command)
          return Success(build_event(command)) unless state.failure
          return Success(nil) if same_failure?(state.failure, command)

          Failure(already_failed(state, command))
        end

        private

        def target_matches?(state, command)
          state.planned.process_step_id == command.process_step_id &&
            state.planned.target_command_id == command.target_command_id
        end

        def build_event(command)
          Events::ProcessStepDispatchFailedV1.new(
            process_step_id: command.process_step_id,
            target_command_id: command.target_command_id,
            code: command.code,
            reason: command.reason,
            retryable: command.retryable
          )
        end

        def same_failure?(failure, command)
          failure.target_command_id == command.target_command_id &&
            failure.code == command.code &&
            failure.reason == command.reason &&
            failure.retryable == command.retryable
        end

        def target_mismatch(state, command)
          OutcomeError.new(
            code: :process_step_target_mismatch,
            message: "Process step does not allocate the failed target command",
            details: {
              process_step_id: command.process_step_id,
              expected_target_command_id: state.planned.target_command_id,
              requested_target_command_id: command.target_command_id
            }
          )
        end

        def already_failed(state, command)
          OutcomeError.new(
            code: :process_step_dispatch_already_failed,
            message: "Process step already records another terminal dispatch failure",
            details: {
              process_step_id: command.process_step_id,
              existing_code: state.failure.code,
              requested_code: command.code
            }
          )
        end
      end
    end
  end
end
