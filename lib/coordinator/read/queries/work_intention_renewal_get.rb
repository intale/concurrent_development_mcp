# frozen_string_literal: true

module Coordinator::Read
  module Queries
    class WorkIntentionRenewalGet < Dry::Operation
      def initialize(contract: Contracts::WorkIntentionRenewalGet.new, renewals: Repositories::WorkIntentionRenewals.new)
        @contract, @renewals = contract, renewals
      end

      def call(input)
        validation = @contract.call(input)
        if validation.failure?
          return result(status: "invalid", summary: "work_intention_renewal_get input is invalid.",
            data: QueryResultV1::DomainError.new(code: "invalid_input", message: "Invalid renewal ID", details: validation.errors.to_h))
        end
        renewal = @renewals.fetch(renewal_id: validation[:renewal_id], task_id: validation[:task_id])
        unless renewal
          return result(status: "not_found", summary: "No projected renewal is currently available.",
            data: QueryResultV1::DomainError.new(code: "renewal_not_observed", message: "The read side has not observed this renewal",
              details: validation.to_h))
        end
        result(status: "ok", summary: "Latest available renewal Saga progress; completed member effects are not rolled back.",
          data: QueryResultV1::WorkIntentionRenewalData.new(renewal:))
      end

      private

      def result(status:, summary:, data:)
        QueryResultV1.new(status:, summary:, command_id: nil, receipt: nil, context_token: nil, data:, warnings: [], next_actions: [])
      end
    end
  end
end
