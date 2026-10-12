# frozen_string_literal: true

module Coordinator::Write
  module WorkIntentionRenewals
    class Request
      def call(command:, expires_at:, assignments:)
        [ Events::OptimisticSagas::WorkIntentionSetRenewalRequestedV1.new(
          renewal_id: command.command_id, intention_set_id: command.intention_set_id,
          attempt_id: command.attempt_id, expires_at:
        ), *assignments ]
      end
    end
  end
end
