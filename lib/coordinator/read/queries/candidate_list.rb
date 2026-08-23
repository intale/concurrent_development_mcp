# frozen_string_literal: true

module Coordinator::Read
  module Queries
    class CandidateList < Dry::Operation
      def initialize(contract: Contracts::CandidateList.new, candidates: Repositories::Candidates.new)
        @contract = contract
        @candidates = candidates
      end

      def call(input)
        validated = @contract.call(input)
        return invalid_result(validated.errors.to_h) if validated.failure?

        query = CandidateListQueryV1.new(
          attempt_id: validated[:attempt_id],
          after_global_position: validated[:after_global_position],
          limit: validated[:limit] || 20
        )
        QueryResultV1.new(
          status: "ok",
          summary: "Latest available projected Candidate checkpoints for this Attempt.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::CandidatePageData.new(page: @candidates.page(query)),
          warnings: [],
          next_actions: []
        )
      end

      private

      def invalid_result(details)
        QueryResultV1.new(
          status: "invalid",
          summary: "candidate_list input is invalid.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "invalid_input",
            message: "candidate_list input is invalid",
            details:
          ),
          warnings: [],
          next_actions: []
        )
      end
    end
  end
end
