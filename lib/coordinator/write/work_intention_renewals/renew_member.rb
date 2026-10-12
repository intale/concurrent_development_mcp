# frozen_string_literal: true

module Coordinator::Write
  module WorkIntentionRenewals
    class RenewMember
      include Dry::Monads[:result]

      def call(state:, assignment:, request:, command:, now:)
        matches = request && assignment && assignment.renew_command_id == command.command_id &&
          request.renewal_id == command.renewal_id && request.intention_set_id == command.intention_set_id &&
          request.attempt_id == command.attempt_id && request.expires_at == command.expires_at &&
          assignment.intention_id == command.intention_id && assignment.resource_id == command.resource_id &&
          assignment.fencing_token == command.fencing_token && state.intention_id == command.intention_id &&
          state.resource_id == command.resource_id && state.fencing_token == command.fencing_token &&
          state.set_id == command.intention_set_id && state.attempt_id == command.attempt_id &&
          state.change_set_id == command.change_set_id && state.work_item_id == command.work_item_id &&
          state.agent_id == command.actor.id
        return Failure(error(:work_intention_reference_mismatch, "Renewal member no longer matches its assigned identity", command)) unless matches
        return Failure(error(:work_intention_set_inactive, "Renewal member is withdrawn or expired", command)) unless state.active_at?(now)
        return Success(nil) if state.expires_at >= command.expires_at

        Success(Events::ResourceWorkIntentionRenewedV1.new(
          intention_id: command.intention_id, resource_id: command.resource_id,
          fencing_token: command.fencing_token, expires_at: command.expires_at))
      end

      private

      def error(code, message, command)
        OutcomeError.new(code:, message:, details: { command_id: command.command_id })
      end
    end
  end
end
