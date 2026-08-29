# frozen_string_literal: true

module Coordinator::Read
  module Queries
    class ResourceGet < Dry::Operation
      def initialize(contract: Contracts::ResourceGet.new, resources: Repositories::Resources.new)
        @contract = contract
        @resources = resources
      end

      def call(input)
        validated = @contract.call(input)
        return invalid_result(validated.errors.to_h) if validated.failure?

        query = ResourceGetQueryV1.new(resource_id: validated[:resource_id])
        resource = @resources.fetch(query.resource_id)
        return not_found_result(query) unless resource

        QueryResultV1.new(
          status: "ok",
          summary: "Latest available projected Resource lifecycle; this view may lag authoritative writes.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::ResourceData.new(resource:),
          warnings: [],
          next_actions: []
        )
      end

      private

      def not_found_result(query)
        QueryResultV1.new(
          status: "not_found",
          summary: "No projected Resource is currently available for this UUID.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "resource_not_observed",
            message: "The read side has not observed this Resource",
            details: { resource_id: query.resource_id }
          ),
          warnings: [],
          next_actions: []
        )
      end

      def invalid_result(details)
        QueryResultV1.new(
          status: "invalid",
          summary: "resource_get input is invalid.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "invalid_input",
            message: "resource_get input is invalid",
            details:
          ),
          warnings: [],
          next_actions: []
        )
      end
    end
  end
end
