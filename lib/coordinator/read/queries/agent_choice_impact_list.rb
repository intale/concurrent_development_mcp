# frozen_string_literal: true

module Coordinator::Read
  module Queries
    class AgentChoiceImpactList < Dry::Operation
      def initialize(
        contract: Contracts::AgentChoiceImpactList.new,
        impacts: Repositories::AgentChoiceImpacts.new
      )
        @contract = contract
        @impacts = impacts
      end

      def call(input)
        validated = @contract.call(input)
        return invalid_result(validated.errors.to_h) if validated.failure?

        query = AgentChoiceImpactListQueryV1.new(
          attempt_id: validated[:attempt_id],
          after_global_position: validated[:after_global_position],
          limit: validated[:limit] || 20
        )
        QueryResultV1.new(
          status: "ok",
          summary: "Latest available projected AgentChoice impact assessments.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::AgentChoiceImpactPageData.new(page: @impacts.page(query)),
          warnings: [],
          next_actions: []
        )
      end

      private

      def invalid_result(details)
        QueryResultV1.new(
          status: "invalid",
          summary: "agent_choice_impact_list input is invalid.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "invalid_input",
            message: "agent_choice_impact_list input is invalid",
            details:
          ),
          warnings: [],
          next_actions: []
        )
      end
    end
  end
end
