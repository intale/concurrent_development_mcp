# frozen_string_literal: true

module Coordinator::Read
  module Queries
    class VerificationObligationsList < Dry::Operation
      def initialize(
        contract: Contracts::VerificationObligationList.new,
        obligations: Repositories::VerificationObligations.new
      )
        @contract = contract
        @obligations = obligations
      end

      def call(input)
        validated = @contract.call(input)
        return invalid_result(validated.errors.to_h) if validated.failure?

        query = VerificationObligationListQueryV1.new(
          change_set_id: validated[:change_set_id],
          candidate_id: validated[:candidate_id],
          work_item_id: validated[:work_item_id],
          repository_id: validated[:repository_id],
          kind: validated[:kind],
          enforcement: validated[:enforcement],
          status: validated[:status] || "open",
          after_global_position: validated[:after_global_position],
          limit: validated[:limit] || 20
        )
        QueryResultV1.new(
          status: "ok",
          summary: "Latest available projected verification obligations; an empty page may reflect projection lag.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::VerificationObligationPageData.new(
            page: @obligations.page(query)
          ),
          warnings: [],
          next_actions: []
        )
      end

      private

      def invalid_result(details)
        QueryResultV1.new(
          status: "invalid",
          summary: "verification_obligations_list input is invalid.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "invalid_input",
            message: "verification_obligations_list input is invalid",
            details:
          ),
          warnings: [],
          next_actions: []
        )
      end
    end
  end
end
