# frozen_string_literal: true

module Coordinator::Read
  module Queries
    class CandidateGet < Dry::Operation
      def initialize(contract: Contracts::CandidateGet.new, candidates: Repositories::Candidates.new)
        @contract = contract
        @candidates = candidates
      end

      def call(input)
        validated = @contract.call(input)
        return invalid_result(validated.errors.to_h) if validated.failure?

        query = CandidateGetQueryV1.new(candidate_id: validated[:candidate_id])
        candidate = @candidates.fetch(query.candidate_id)
        return not_found_result(query.candidate_id) unless candidate

        QueryResultV1.new(
          status: "ok",
          summary: "Latest available projected Candidate evidence; attribution is unverified.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::CandidateData.new(candidate:),
          warnings: available_warnings(candidate),
          next_actions: []
        )
      end

      private

      def available_warnings(candidate)
        warnings = []
        warnings << "The Candidate manifest has not yet been observed by this projection." unless candidate.manifest
        if candidate.build_context_digest && !candidate.build_context
          warnings << "The Candidate build context has not yet been observed by this projection."
        end
        warnings.freeze
      end

      def not_found_result(candidate_id)
        QueryResultV1.new(
          status: "not_found",
          summary: "No projected Candidate submission is currently available for this Candidate ID.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "candidate_not_observed",
            message: "The read side has not observed this Candidate submission",
            details: { candidate_id: }
          ),
          warnings: [],
          next_actions: []
        )
      end

      def invalid_result(details)
        QueryResultV1.new(
          status: "invalid",
          summary: "candidate_get input is invalid.",
          command_id: nil,
          receipt: nil,
          context_token: nil,
          data: QueryResultV1::DomainError.new(
            code: "invalid_input",
            message: "candidate_get input is invalid",
            details:
          ),
          warnings: [],
          next_actions: []
        )
      end
    end
  end
end
