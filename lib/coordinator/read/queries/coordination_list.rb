# frozen_string_literal: true

module Coordinator::Read
  module Queries
    class CoordinationList < Dry::Operation
      DEFAULT_STATUSES = %w[planning active completed].freeze

      def initialize(
        contract: Contracts::CoordinationList.new,
        discovery: Repositories::CoordinationDiscovery.new
      )
        @contract = contract
        @discovery = discovery
      end

      def call(input)
        validated = @contract.call(input)
        return invalid_result(validated.errors.to_h) if validated.failure?

        page = @discovery.page(build_query(validated.to_h))
        QueryResultV1.new(
          status: "ok",
          summary: "Latest available project-scoped coordination discovery.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::CoordinationPageData.new(page:),
          warnings: [ "Coordination discovery is projection-derived and may lag authoritative commands." ],
          next_actions: next_actions(page)
        )
      end

      private

      def build_query(attributes)
        CoordinationListQueryV1.new(
          scope: attributes.fetch(:scope),
          repository_id: attributes[:repository_id],
          statuses: (attributes[:statuses] || DEFAULT_STATUSES).uniq.sort_by(&:b),
          cursor: attributes[:cursor] && CoordinationPageV1::Cursor.new(attributes.fetch(:cursor)),
          limit: attributes[:limit] || 20
        )
      end

      def next_actions(page)
        actions = page.items.map do |item|
          NextAction.new(
            tool: "coord_context",
            arguments: NextAction::ChangeSetArguments.new(change_set_id: item.change_set_id)
          )
        end
        return actions unless page.continuation_cursor

        actions + [
          NextAction.new(
            tool: "coordination_list",
            arguments: NextAction::CoordinationListArguments.new(
              scope: page.scope,
              repository_id: page.repository_id,
              statuses: page.statuses,
              cursor: page.continuation_cursor,
              limit: Types::COORDINATION_DISCOVERY_MAXIMUM_ITEMS
            )
          )
        ]
      end

      def invalid_result(details)
        QueryResultV1.new(
          status: "invalid",
          summary: "coordination_list input is invalid.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "invalid_input",
            message: "coordination_list input is invalid",
            details:
          ),
          warnings: [],
          next_actions: []
        )
      end
    end
  end
end
