# frozen_string_literal: true

module Coordinator::Read
  module Queries
    class AgentChoiceGet < Dry::Operation
      def initialize(
        contract: Contracts::AgentChoiceGet.new,
        choices: Repositories::AgentChoices.new
      )
        @contract = contract
        @choices = choices
      end

      def call(input)
        validated = @contract.call(input)
        return invalid_result(validated.errors.to_h) if validated.failure?

        query = AgentChoiceGetQueryV1.new(choice_id: validated[:choice_id])
        choice = @choices.fetch(query.choice_id)
        return not_found_result(query.choice_id) unless choice

        QueryResultV1.new(
          status: "ok",
          summary: "Latest available projected AgentChoice evidence.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::AgentChoiceData.new(choice:),
          warnings: [],
          next_actions: next_actions(choice)
        )
      end

      private

      def next_actions(choice)
        return [] unless choice.observation_status == "invalidated"

        [
          Coordinator::Write::NextAction.new(
            tool: "decision_resolve",
            arguments: Coordinator::Write::NextAction::DecisionResolutionArguments.new(
              topic_id: choice.choice_type,
              context: choice.context
            )
          )
        ]
      end

      def not_found_result(choice_id)
        QueryResultV1.new(
          status: "not_found",
          summary: "No projected AgentChoice evidence exists for the supplied Choice ID.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "agent_choice_not_observed",
            message: "The read side has not observed this AgentChoice",
            details: { choice_id: }
          ),
          warnings: [],
          next_actions: []
        )
      end

      def invalid_result(details)
        QueryResultV1.new(
          status: "invalid",
          summary: "agent_choice_get input is invalid.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "invalid_input",
            message: "agent_choice_get input is invalid",
            details:
          ),
          warnings: [],
          next_actions: []
        )
      end
    end
  end
end
