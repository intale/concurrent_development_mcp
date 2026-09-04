# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module VerificationObligationWaivers
      class Waive
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:)
          denial = denied(state, command)
          return Failure(denial) if denial

          event = Events::VerificationObligationWaivedV2.new(
            obligation_id: command.obligation_id,
            reason: command.reason
          )
          Success(
            EventPlan.new(
              writes: [
                EventWrite.new(
                  stream: @stream_factory.verification_obligation(command.obligation_id),
                  event:
                )
              ]
            )
          )
        end

        private

        def denied(state, command)
          return error(:verification_obligation_not_found, "Verification obligation does not exist", command) if state.absent?
          unless command.actor.kind == "user"
            return error(
              :verification_obligation_waiver_requires_user,
              "Verification obligation waiver requires user attribution",
              command
            )
          end
          unless command.obligation_validity_input_digest == state.obligation.validity_input_digest
            return error(
              :verification_obligation_binding_stale,
              "Verification obligation waiver is bound to stale inputs",
              command,
              current_validity_input_digest: state.obligation.validity_input_digest
            )
          end

          terminal_denial(state, command)
        end

        def terminal_denial(state, command)
          case state.status
          when "open" then nil
          when "waived"
            error(
              :verification_obligation_already_waived,
              "Verification obligation is already waived",
              command,
              status: state.status
            )
          else
            error(
              :verification_obligation_terminal,
              "Verification obligation cannot be waived from its current status",
              command,
              status: state.status
            )
          end
        end

        def error(code, message, command, details = {})
          OutcomeError.new(
            code:,
            message:,
            details: { obligation_id: command.obligation_id }.merge(details)
          )
        end
      end
    end
  end
end
