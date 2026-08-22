# frozen_string_literal: true

module Coordinator::Read
  module Queries
    class DecisionInterpretationList < Dry::Operation
      def initialize(
        contract: Contracts::DecisionInterpretationList.new,
        interpretations: Repositories::DecisionInterpretations.new
      )
        @contract = contract
        @interpretations = interpretations
      end

      def call(input)
        validated = @contract.call(input)
        return invalid_result(validated.errors.to_h) if validated.failure?

        query = InterpretationListQueryV1.new(
          message_id: validated[:message_id],
          after_revision: validated[:after_revision] || -1,
          limit: validated[:limit] || 20
        )
        page = @interpretations.page(query)
        return not_found_result(query.message_id) if page.records.empty? && query.after_revision == -1

        QueryResultV1.new(
          status: "ok",
          summary: "Available atomic interpretation proposals.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::InterpretationPageData.new(
            page: InterpretationPageV1.new(
              message_id: query.message_id,
              interpretations: page.records,
              next_after_revision: page.next_after_revision
            )
          ),
          warnings: [],
          next_actions: []
        )
      end

      private

      def not_found_result(message_id)
        QueryResultV1.new(
          status: "not_found",
          summary: "No projected interpretation proposals exist for the supplied message ID.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "interpretations_not_observed",
            message: "The read side has not observed an interpretation proposal",
            details: { message_id: }
          ),
          warnings: [],
          next_actions: []
        )
      end

      def invalid_result(details)
        QueryResultV1.new(
          status: "invalid",
          summary: "decision_interpretation_list input is invalid.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "invalid_input",
            message: "decision_interpretation_list input is invalid",
            details:
          ),
          warnings: [],
          next_actions: []
        )
      end
    end
  end
end
