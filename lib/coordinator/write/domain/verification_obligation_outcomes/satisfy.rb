# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module VerificationObligationOutcomes
      class Satisfy
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:)
          return terminal_failure(state, command) if state.terminal?

          observations = command.selected_evidence_ids.map { state.observation(_1) }
          valid = observations.none?(&:nil?) &&
            state.observation(command.triggering_evidence_id) &&
            observations.map { _1.evidence.evidence_kind } == state.definition.required_evidence &&
            observations.all? { _1.evidence.assessment.conclusion == "passed" }
          unless valid
            return Failure(
              OutcomeError.new(
                code: :verification_obligation_not_satisfied,
                message: "Submitted evidence does not satisfy this verification obligation",
                details: { obligation_id: command.obligation_id }
              )
            )
          end

          events = observations.map do |observation|
            Events::VerificationObligationEvidenceSelectedV1.new(
              obligation_id: command.obligation_id,
              evidence_id: observation.evidence.evidence_id
            )
          end
          events << Events::VerificationObligationSatisfiedV2.new(obligation_id: command.obligation_id)
          Success(plan(command.obligation_id, events))
        end

        private

        def plan(obligation_id, events)
          stream = @stream_factory.verification_obligation(obligation_id)
          EventPlan.new(writes: events.map { EventWrite.new(stream:, event: _1) })
        end

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
