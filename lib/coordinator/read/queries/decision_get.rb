# frozen_string_literal: true

module Coordinator::Read
  module Queries
    class DecisionGet < Dry::Operation
      def initialize(
        contract: Contracts::DecisionGet.new,
        governance: Repositories::DecisionGovernance.new
      )
        @contract = contract
        @governance = governance
      end

      def call(input)
        validated = @contract.call(input)
        return invalid_result(validated.errors.to_h) if validated.failure?

        query = DecisionGetQueryV1.new(decision_id: validated[:decision_id])
        decision = @governance.fetch(query.decision_id)
        return not_found_result(query.decision_id) unless decision

        QueryResultV1.new(
          status: "ok",
          summary: "Latest available projected Decision evidence.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DecisionData.new(decision:),
          warnings: [],
          next_actions: []
        )
      end

      private

      def not_found_result(decision_id)
        QueryResultV1.new(
          status: "not_found",
          summary: "No projected Decision evidence exists for the supplied Decision ID.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "decision_not_observed",
            message: "The read side has not observed this Decision",
            details: { decision_id: }
          ),
          warnings: [],
          next_actions: []
        )
      end

      def invalid_result(details)
        QueryResultV1.new(
          status: "invalid",
          summary: "decision_get input is invalid.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "invalid_input",
            message: "decision_get input is invalid",
            details:
          ),
          warnings: [],
          next_actions: []
        )
      end
    end
  end
end
