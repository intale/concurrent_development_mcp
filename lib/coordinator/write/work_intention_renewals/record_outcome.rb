# frozen_string_literal: true

module Coordinator::Write
  module WorkIntentionRenewals
    class RecordOutcome
      include Dry::Monads[:result]

      def call(state:, command:)
        assignment = state.assignments.find { _1.intention_id == command.intention_id }
        unless assignment && assignment.outcome_command_id == command.command_id && state.request.renewal_id == command.renewal_id
          return Failure(OutcomeError.new(code: :command_not_found, message: "Assigned renewal step does not exist",
            details: { command_id: command.command_id }))
        end
        existing = state.outcome(command.intention_id)
        return Success([]) if existing
        return Failure(OutcomeError.new(code: :command_terminal, message: "Renewal already has a terminal outcome",
          details: { command_id: command.command_id })) if state.terminal

        if command.failure
          Success([
            Events::OptimisticSagas::WorkIntentionRenewalFailedV1.new(
              renewal_id: command.renewal_id, intention_id: command.intention_id, **command.failure.to_h),
            Events::OptimisticSagas::WorkIntentionSetRenewalFailedV1.new(renewal_id: command.renewal_id)
          ])
        else
          events = [ Events::OptimisticSagas::WorkIntentionRenewalCompletedV1.new(
            renewal_id: command.renewal_id, intention_id: command.intention_id, renewal_event: command.renewal_event) ]
          if state.pending.length == 1
            events << Events::OptimisticSagas::WorkIntentionSetRenewalCompletedV1.new(renewal_id: command.renewal_id)
          end
          Success(events)
        end
      end
    end
  end
end
