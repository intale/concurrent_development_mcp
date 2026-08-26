# frozen_string_literal: true

module Coordinator::Read
  module Queries
    class RepositoryList < Dry::Operation
      def initialize(
        contract: Contracts::RepositoryList.new,
        catalog: Repositories::RepositoryCatalog.new
      )
        @contract = contract
        @catalog = catalog
      end

      def call(input)
        validated = @contract.call(input)
        return invalid_result(validated.errors.to_h) if validated.failure?

        query = RepositoryListQueryV1.new(
          scope: validated[:scope],
          after_repository_id: validated[:after_repository_id],
          limit: validated[:limit] || 20
        )
        QueryResultV1.new(
          status: "ok",
          summary: "Available projected Repository registrations in deterministic Repository-ID order.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::RepositoryPageData.new(page: @catalog.page(query)),
          warnings: [],
          next_actions: []
        )
      end

      private

      def invalid_result(details)
        QueryResultV1.new(
          status: "invalid",
          summary: "repository_list input is invalid.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "invalid_input",
            message: "repository_list input is invalid",
            details:
          ),
          warnings: [],
          next_actions: []
        )
      end
    end
  end
end
