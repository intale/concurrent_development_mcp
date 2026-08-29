# frozen_string_literal: true

module Coordinator::Read
  module Queries
    class ResourceList < Dry::Operation
      def initialize(contract: Contracts::ResourceList.new, resources: Repositories::Resources.new)
        @contract = contract
        @resources = resources
      end

      def call(input)
        validated = @contract.call(input)
        return invalid_result(validated.errors.to_h) if validated.failure?

        query = ResourceListQueryV1.new(
          repository_id: validated[:repository_id],
          kind: validated[:kind],
          lifecycle_status: validated[:lifecycle_status],
          after_resource_id: validated[:after_resource_id],
          limit: validated[:limit] || 20
        )
        QueryResultV1.new(
          status: "ok",
          summary: "Latest available projected Resources in deterministic UUID order; entries may lag authoritative writes.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::ResourcePageData.new(page: @resources.page(query)),
          warnings: [],
          next_actions: []
        )
      end

      private

      def invalid_result(details)
        QueryResultV1.new(
          status: "invalid",
          summary: "resource_list input is invalid.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "invalid_input",
            message: "resource_list input is invalid",
            details:
          ),
          warnings: [],
          next_actions: []
        )
      end
    end
  end
end
