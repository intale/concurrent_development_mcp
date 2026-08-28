# frozen_string_literal: true

module Coordinator::Read
  module Queries
    class DecisionList < Dry::Operation
      def initialize(
        contract: Contracts::DecisionList.new,
        governance: Repositories::DecisionGovernance.new
      )
        @contract = contract
        @governance = governance
      end

      def call(input)
        validated = @contract.call(input)
        return invalid_result(validated.errors.to_h) if validated.failure?

        page = @governance.page(
          DecisionListQueryV1.new(
            repository_id: validated[:repository_id],
            topic_id: validated[:topic_id],
            policy_status: validated[:policy_status],
            after_decision_id: validated[:after_decision_id],
            limit: validated[:limit] || 20
          )
        )
        QueryResultV1.new(
          status: "ok",
          summary: "Latest available Decisions for the exact Repository scope.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DecisionPageData.new(page:),
          warnings: [ "Decision discovery is projection-derived and may lag authoritative policy facts." ],
          next_actions: next_actions(page)
        )
      end

      private

      def next_actions(page)
        actions = page.items.map do |decision|
          Coordinator::Write::NextAction.new(
            tool: "decision_get",
            arguments: Coordinator::Write::NextAction::DecisionArguments.new(
              decision_id: decision.decision_id
            )
          )
        end
        return actions unless page.next_decision_id

        actions + [
          NextAction.new(
            tool: "decision_list",
            arguments: NextAction::DecisionListArguments.new(
              repository_id: page.repository_id,
              topic_id: page.topic_id,
              policy_status: page.policy_status,
              after_decision_id: page.next_decision_id,
              limit: Types::DECISION_DISCOVERY_MAXIMUM_ITEMS
            )
          )
        ]
      end

      def invalid_result(details)
        QueryResultV1.new(
          status: "invalid",
          summary: "decision_list input is invalid.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "invalid_input",
            message: "decision_list input is invalid",
            details:
          ),
          warnings: [],
          next_actions: []
        )
      end
    end
  end
end
