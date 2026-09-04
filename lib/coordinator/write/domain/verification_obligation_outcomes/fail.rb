# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module VerificationObligationOutcomes
      class Fail
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:)
          return terminal_failure(state, command) if state.terminal?

          observation = state.observation(command.triggering_evidence_id)
          unless observation&.evidence&.assessment&.conclusion == "failed"
            return Failure(
              OutcomeError.new(
                code: :verification_obligation_not_failed,
                message: "Submitted evidence does not fail this verification obligation",
                details: { obligation_id: command.obligation_id }
              )
            )
          end

          selection = Events::VerificationObligationEvidenceSelectedV1.new(
            obligation_id: command.obligation_id,
            evidence_id: observation.evidence.evidence_id
          )
          failure = Events::VerificationObligationFailedV2.new(
            obligation_id: command.obligation_id,
            reason: command.reason
          )
          stream = @stream_factory.verification_obligation(command.obligation_id)
          Success(EventPlan.new(writes: [ selection, failure ].map { EventWrite.new(stream:, event: _1) }))
        end

        private

        def terminal_failure(state, command)
          Failure(
            OutcomeError.new(
              code: :verification_obligation_terminal,
              message: "Verification obligation is already terminal",
              details: { obligation_id: command.obligation_id, status: state.terminal_status }
            )
          )
        end
      end
    end
  end
end
